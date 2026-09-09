import { Inject, Injectable } from '@nestjs/common';
import { sql } from 'kysely';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException, notFound } from '../common/errors/domain.exception';
import { UploadsService } from '../uploads/uploads.service';
import type { HoldStatusEnum, HoldTypeEnum } from '../database/schema';
import type {
  CreateHoldBatchPayload,
  CreateHoldSetPayload,
  HoldDTO,
  HoldSetDTO,
  UpdateHoldPayload,
} from './dto/inventory.dto';

interface HoldRow {
  id: string;
  set_id: string;
  image_crop_url: string;
  type_category: HoldTypeEnum;
  status: HoldStatusEnum;
  difficulty_rating_weight: number;
  bounding_box_data: { width_px: number; height_px: number } | null;
}

/** 04 §2.8 — Inventario (RF-2.1, RF-2.2, RF-2.3) */
@Injectable()
export class InventoryService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly uploads: UploadsService,
  ) {}

  async createSet(
    gymId: string,
    payload: CreateHoldSetPayload,
    creatorId: string,
  ): Promise<HoldSetDTO> {
    const row = await this.db
      .insertInto('hold_sets')
      .values({
        gym_id: gymId,
        creator_id: creatorId,
        name: payload.name,
        color_hex: payload.colorHex.toUpperCase(),
      })
      .returning('id')
      .executeTakeFirstOrThrow();

    return this.findSet(row.id);
  }

  async findSetsByGym(gymId: string, colorHex?: string): Promise<HoldSetDTO[]> {
    let query = this.setQuery().where('hs.gym_id', '=', gymId);
    if (colorHex) query = query.where('hs.color_hex', 'ilike', colorHex);
    const rows = await query.orderBy('hs.name').execute();
    return rows.map(InventoryService.toSetDTO);
  }

  async findSet(setId: string): Promise<HoldSetDTO> {
    const row = await this.setQuery().where('hs.id', '=', setId).executeTakeFirst();
    if (!row) throw notFound('El set de presas');
    return InventoryService.toSetDTO(row);
  }

  async getSetGymId(setId: string): Promise<string> {
    const row = await this.db
      .selectFrom('hold_sets')
      .select('gym_id')
      .where('id', '=', setId)
      .executeTakeFirst();
    if (!row) throw notFound('El set de presas');
    return row.gym_id;
  }

  /**
   * Alta masiva transaccional tras la segmentación en cliente (RF-2.1).
   * `status` se omite a propósito: la BD aplica el default 'available' (§1.3).
   */
  async createHoldsBatch(setId: string, payload: CreateHoldBatchPayload): Promise<HoldDTO[]> {
    const gymId = await this.getSetGymId(setId);

    // 04 §5: cada URL debe vivir bajo `hold_crop/{gymId}/` del bucket propio.
    for (const hold of payload.holds) {
      this.uploads.assertUrlInScope(hold.imageCropUrl, 'hold_crop', gymId);
    }

    const rows = await this.db.transaction().execute(async (trx) =>
      trx
        .insertInto('holds')
        .values(
          payload.holds.map((h) => ({
            set_id: setId,
            image_crop_url: h.imageCropUrl,
            type_category: h.typeCategory,
            difficulty_rating_weight: h.difficultyRatingWeight ?? 1.0,
            bounding_box_data: h.boundingBoxData
              ? (JSON.stringify(h.boundingBoxData) as never)
              : null,
          })),
        )
        .returningAll()
        .execute(),
    );

    return rows.map(InventoryService.toHoldDTO);
  }

  async findHoldsBySet(setId: string, status?: HoldStatusEnum): Promise<HoldDTO[]> {
    await this.getSetGymId(setId); // 404 si el set no existe
    let query = this.db.selectFrom('holds').selectAll().where('set_id', '=', setId);
    if (status) query = query.where('status', '=', status);
    const rows = await query.orderBy('created_at').execute();
    return rows.map(InventoryService.toHoldDTO);
  }

  /**
   * RNF-3 (< 500 ms): alimenta el editor. Se apoya en idx_holds_set_status y
   * en idx_hold_sets_gym; nunca hace un scan de `holds`.
   */
  async findAvailableByGym(gymId: string, setIds?: string[]): Promise<HoldDTO[]> {
    let query = this.db
      .selectFrom('holds as h')
      .innerJoin('hold_sets as hs', 'hs.id', 'h.set_id')
      .select([
        'h.id',
        'h.set_id',
        'h.image_crop_url',
        'h.type_category',
        'h.status',
        'h.difficulty_rating_weight',
        'h.bounding_box_data',
      ])
      .where('hs.gym_id', '=', gymId)
      .where('h.status', '=', 'available');

    if (setIds && setIds.length > 0) query = query.where('h.set_id', 'in', setIds);

    const rows = await query.orderBy('h.set_id').orderBy('h.id').execute();
    return rows.map(InventoryService.toHoldDTO);
  }

  async findHold(holdId: string): Promise<HoldDTO> {
    const row = await this.db
      .selectFrom('holds')
      .selectAll()
      .where('id', '=', holdId)
      .executeTakeFirst();
    if (!row) throw notFound('La presa');
    return InventoryService.toHoldDTO(row);
  }

  async getHoldGymId(holdId: string): Promise<string> {
    const row = await this.db
      .selectFrom('holds as h')
      .innerJoin('hold_sets as hs', 'hs.id', 'h.set_id')
      .select('hs.gym_id')
      .where('h.id', '=', holdId)
      .executeTakeFirst();
    if (!row) throw notFound('La presa');
    return row.gym_id;
  }

  /**
   * 04 §2.8: sacar una presa de `in_use` por vía directa está prohibido —
   * esa transición es potestad exclusiva de los triggers.
   */
  async updateHold(holdId: string, payload: UpdateHoldPayload): Promise<HoldDTO> {
    const current = await this.findHold(holdId);

    if (payload.status !== undefined && current.status === 'in_use') {
      throw new DomainException(
        'VALIDATION_FAILED',
        'La presa está colocada en una ruta activa: su estado lo libera el desmontaje, no la API.',
      );
    }

    const patch = {
      ...(payload.typeCategory !== undefined ? { type_category: payload.typeCategory } : {}),
      ...(payload.difficultyRatingWeight !== undefined
        ? { difficulty_rating_weight: payload.difficultyRatingWeight }
        : {}),
      ...(payload.status !== undefined ? { status: payload.status } : {}),
    };

    if (Object.keys(patch).length === 0) return current;

    await this.db.updateTable('holds').set(patch).where('id', '=', holdId).execute();
    return this.findHold(holdId);
  }

  private setQuery() {
    return this.db
      .selectFrom('hold_sets as hs')
      .select((eb) => [
        'hs.id',
        'hs.gym_id',
        'hs.creator_id',
        'hs.name',
        'hs.color_hex',
        eb
          .selectFrom('holds as h')
          .select(sql<number>`count(*)::int`.as('c'))
          .whereRef('h.set_id', '=', 'hs.id')
          .as('holds_count'),
        eb
          .selectFrom('holds as h')
          .select(sql<number>`count(*)::int`.as('c'))
          .whereRef('h.set_id', '=', 'hs.id')
          .where('h.status', '=', 'available')
          .as('available_count'),
      ]);
  }

  private static toSetDTO(row: {
    id: string;
    gym_id: string;
    creator_id: string | null;
    name: string;
    color_hex: string;
    holds_count: number | null;
    available_count: number | null;
  }): HoldSetDTO {
    return {
      id: row.id,
      gymId: row.gym_id,
      ...(row.creator_id ? { creatorId: row.creator_id } : {}),
      name: row.name,
      colorHex: row.color_hex,
      holdsCount: row.holds_count ?? 0,
      availableCount: row.available_count ?? 0,
    };
  }

  /** Mapeo snake_case -> camelCase (04 §3). */
  static toHoldDTO(row: HoldRow): HoldDTO {
    return {
      id: row.id,
      setId: row.set_id,
      imageCropUrl: row.image_crop_url,
      typeCategory: row.type_category,
      status: row.status,
      difficultyRatingWeight: row.difficulty_rating_weight,
      ...(row.bounding_box_data ? { boundingBoxData: row.bounding_box_data } : {}),
    };
  }
}
