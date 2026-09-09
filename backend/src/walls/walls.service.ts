import { Inject, Injectable } from '@nestjs/common';
import { sql } from 'kysely';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException, notFound } from '../common/errors/domain.exception';
import { MembershipService } from '../auth/membership.service';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import type { CreateWallPayload, UpdateWallPayload, WallDTO } from './dto/wall.dto';

interface WallRow {
  id: string;
  gym_id: string;
  creator_id: string | null;
  name: string;
  photo_url: string;
  width_cm: number;
  height_cm: number;
  default_incline_deg: number;
  default_grade_system_id: string | null;
  is_public: boolean;
  active_routes_count: number | null;
}

@Injectable()
export class WallsService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly memberships: MembershipService,
  ) {}

  async create(gymId: string, payload: CreateWallPayload, creatorId: string): Promise<WallDTO> {
    if (payload.defaultGradeSystemId) {
      await this.assertGradeSystemUsableBy(gymId, payload.defaultGradeSystemId);
    }

    const row = await this.db
      .insertInto('walls')
      .values({
        gym_id: gymId,
        creator_id: creatorId,
        name: payload.name,
        photo_url: payload.photoUrl,
        width_cm: payload.widthCm,
        height_cm: payload.heightCm,
        default_incline_deg: payload.defaultInclineDeg,
        default_grade_system_id: payload.defaultGradeSystemId ?? null,
        is_public: payload.isPublic ?? false,
      })
      .returning('id')
      .executeTakeFirstOrThrow();

    return this.findOne(row.id);
  }

  /** 04 §2.7: miembro ve todo; el resto sólo los muros `isPublic`. */
  async findAllByGym(gymId: string, user?: AuthenticatedUser): Promise<WallDTO[]> {
    const isMember =
      !!user && (user.role === 'admin' || (await this.memberships.isAuthorizedMember(user.id, gymId)));

    let query = this.baseQuery().where('w.gym_id', '=', gymId);
    if (!isMember) query = query.where('w.is_public', '=', true);

    const rows = await query.orderBy('w.name').execute();
    return rows.map(WallsService.toDTO);
  }

  async findOne(wallId: string): Promise<WallDTO> {
    const row = await this.baseQuery().where('w.id', '=', wallId).executeTakeFirst();
    if (!row) throw notFound('El muro');
    return WallsService.toDTO(row);
  }

  /** Devuelve las columnas que necesita la validación de grados (04 §2.9.1 paso 2). */
  async findRawOrThrow(wallId: string) {
    const row = await this.db
      .selectFrom('walls')
      .select(['id', 'gym_id', 'creator_id', 'default_grade_system_id'])
      .where('id', '=', wallId)
      .executeTakeFirst();
    if (!row) throw notFound('El muro');
    return row;
  }

  /** 04 §2.7: creador del muro o admin del gym. */
  async update(wallId: string, payload: UpdateWallPayload, user: AuthenticatedUser): Promise<WallDTO> {
    const wall = await this.findRawOrThrow(wallId);

    const allowed =
      user.role === 'admin' ||
      wall.creator_id === user.id ||
      (await this.memberships.isAdmin(user.id, wall.gym_id));
    if (!allowed) {
      throw new DomainException(
        'NOT_GYM_ADMIN',
        'Sólo el creador del muro o un administrador del boulder puede editarlo.',
      );
    }

    if (payload.defaultGradeSystemId) {
      await this.assertGradeSystemUsableBy(wall.gym_id, payload.defaultGradeSystemId);
    }

    const patch = {
      ...(payload.name !== undefined ? { name: payload.name } : {}),
      ...(payload.photoUrl !== undefined ? { photo_url: payload.photoUrl } : {}),
      ...(payload.widthCm !== undefined ? { width_cm: payload.widthCm } : {}),
      ...(payload.heightCm !== undefined ? { height_cm: payload.heightCm } : {}),
      ...(payload.defaultInclineDeg !== undefined
        ? { default_incline_deg: payload.defaultInclineDeg }
        : {}),
      ...(payload.defaultGradeSystemId !== undefined
        ? { default_grade_system_id: payload.defaultGradeSystemId }
        : {}),
      ...(payload.isPublic !== undefined ? { is_public: payload.isPublic } : {}),
    };

    if (Object.keys(patch).length > 0) {
      await this.db
        .updateTable('walls')
        .set({ ...patch, updated_at: new Date() })
        .where('id', '=', wallId)
        .execute();
    }
    return this.findOne(wallId);
  }

  /** Una escala privada de otro boulder nunca es asignable a este muro. */
  private async assertGradeSystemUsableBy(gymId: string, systemId: string): Promise<void> {
    const system = await this.db
      .selectFrom('grade_systems')
      .select(['id', 'gym_id'])
      .where('id', '=', systemId)
      .executeTakeFirst();
    if (!system) throw notFound('El sistema de grados');

    if (system.gym_id !== null && system.gym_id !== gymId) {
      throw new DomainException(
        'GRADE_SYSTEM_MISMATCH',
        'Ese sistema de grados pertenece a otro boulder.',
      );
    }
  }

  private baseQuery() {
    return this.db
      .selectFrom('walls as w')
      .select((eb) => [
        'w.id',
        'w.gym_id',
        'w.creator_id',
        'w.name',
        'w.photo_url',
        'w.width_cm',
        'w.height_cm',
        'w.default_incline_deg',
        'w.default_grade_system_id',
        'w.is_public',
        eb
          .selectFrom('routes as r')
          .select(sql<number>`count(*)::int`.as('c'))
          .whereRef('r.wall_id', '=', 'w.id')
          .where('r.status', '=', 'active')
          .as('active_routes_count'),
      ]);
  }

  private static toDTO(row: WallRow): WallDTO {
    return {
      id: row.id,
      gymId: row.gym_id,
      ...(row.creator_id ? { creatorId: row.creator_id } : {}),
      name: row.name,
      photoUrl: row.photo_url,
      widthCm: row.width_cm,
      heightCm: row.height_cm,
      defaultInclineDeg: row.default_incline_deg,
      ...(row.default_grade_system_id
        ? { defaultGradeSystemId: row.default_grade_system_id }
        : {}),
      isPublic: row.is_public,
      activeRoutesCount: row.active_routes_count ?? 0,
    };
  }
}
