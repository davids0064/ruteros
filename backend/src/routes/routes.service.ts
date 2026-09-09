import { Inject, Injectable } from '@nestjs/common';
import { sql, type Transaction } from 'kysely';
import { KYSELY, type Db } from '../database/database.module';
import type { Database, HoldRoleEnum, RouteStatusEnum } from '../database/schema';
import { DomainException, notFound } from '../common/errors/domain.exception';
import { GradesService } from '../grades/grades.service';
import { InventoryService } from '../inventory/inventory.service';
import { MembershipService } from '../auth/membership.service';
import { DifficultyService, type WeightedPlacement } from './difficulty.service';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import type { GradeValueDTO } from '../grades/dto/grade.dto';
import type {
  PlacedHoldDTO,
  RouteCreatePayload,
  RouteDetailDTO,
  RouteSummaryDTO,
  UpdateRoutePayload,
} from './dto/route.dto';

export interface RouteFilters {
  status?: RouteStatusEnum;
  creatorId?: string;
  gradeId?: string;
}

@Injectable()
export class RoutesService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly grades: GradesService,
    private readonly inventory: InventoryService,
    private readonly memberships: MembershipService,
    private readonly difficulty: DifficultyService,
  ) {}

  /** Algoritmo transaccional de 04 §2.9.1. */
  async create(payload: RouteCreatePayload, user: AuthenticatedUser): Promise<RouteDetailDTO> {
    // El `creatorId` del payload es informativo; manda el `sub` del JWT.
    if (payload.creatorId !== user.id) {
      throw new DomainException(
        'NOT_ROUTE_AUTHOR',
        'La autoría de una ruta es siempre la del usuario autenticado.',
      );
    }

    // Paso 1
    const wall = await this.db
      .selectFrom('walls')
      .select(['id', 'gym_id', 'default_grade_system_id'])
      .where('id', '=', payload.wallId)
      .executeTakeFirst();
    if (!wall) throw notFound('El muro');

    await this.assertAuthorizedMember(user, wall.gym_id);

    // Paso 2
    await this.grades.assertGradeBelongsToWallSystem(payload.targetGradeId, wall);

    this.assertNoDuplicateHolds(payload.placedHolds);

    const routeId = await this.db.transaction().execute(async (trx) => {
      // Paso 3: sin FOR UPDATE, dos setters concurrentes reservarían la misma presa.
      await this.lockAndVerifyHolds(trx, payload.placedHolds, wall.gym_id);

      // Paso 4: creator_id = JWT.sub, escrito una sola vez (04 §4.2)
      const route = await trx
        .insertInto('routes')
        .values({
          wall_id: payload.wallId,
          creator_id: user.id,
          title: payload.title,
          target_grade_id: payload.targetGradeId,
          wall_incline_deg: payload.wallInclineDeg,
        })
        .returning('id')
        .executeTakeFirstOrThrow();

      // Paso 5: trigger_mark_hold_in_use marca cada presa 'in_use'.
      await this.insertPlacements(trx, route.id, payload.placedHolds);

      // Paso 6
      await this.recalculateGrade(trx, route.id, payload.wallInclineDeg, wall);

      return route.id;
    });

    // Paso 7: se RELEE el estado; nunca se asume (regla de oro, 04 §0.1).
    return this.findDetail(routeId);
  }

  async findByWall(wallId: string, filters: RouteFilters): Promise<RouteSummaryDTO[]> {
    const wall = await this.db
      .selectFrom('walls')
      .select('id')
      .where('id', '=', wallId)
      .executeTakeFirst();
    if (!wall) throw notFound('El muro');

    let query = this.summaryQuery().where('r.wall_id', '=', wallId);
    if (filters.status) query = query.where('r.status', '=', filters.status);
    if (filters.creatorId) query = query.where('r.creator_id', '=', filters.creatorId);
    if (filters.gradeId) query = query.where('r.target_grade_id', '=', filters.gradeId);

    const rows = await query.orderBy('r.created_at', 'desc').execute();
    return rows.map(RoutesService.toSummary);
  }

  async findDetail(routeId: string): Promise<RouteDetailDTO> {
    const row = await this.summaryQuery().where('r.id', '=', routeId).executeTakeFirst();
    if (!row) throw notFound('La ruta');

    const placements = await this.db
      .selectFrom('placed_holds as ph')
      .innerJoin('holds as h', 'h.id', 'ph.hold_id')
      .select([
        'ph.id',
        'ph.hold_id',
        'ph.x_percent',
        'ph.y_percent',
        'ph.rotation_deg',
        'ph.hold_role',
        'h.set_id',
        'h.image_crop_url',
        'h.type_category',
        'h.status',
        'h.difficulty_rating_weight',
        'h.bounding_box_data',
      ])
      .where('ph.route_id', '=', routeId)
      .orderBy('ph.y_percent', 'desc')
      .execute();

    return {
      ...RoutesService.toSummary(row),
      placedHolds: placements.map((p) => ({
        id: p.id,
        holdId: p.hold_id,
        xPercent: p.x_percent,
        yPercent: p.y_percent,
        rotationDeg: p.rotation_deg,
        role: p.hold_role,
        // El canvas necesita el sprite embebido para pintar sin un segundo viaje.
        hold: InventoryService.toHoldDTO({
          id: p.hold_id,
          set_id: p.set_id,
          image_crop_url: p.image_crop_url,
          type_category: p.type_category,
          status: p.status,
          difficulty_rating_weight: p.difficulty_rating_weight,
          bounding_box_data: p.bounding_box_data,
        }),
      })),
    };
  }

  /** 04 §2.9: `creatorId` inmutable; sólo el autor (o un admin del gym) muta. */
  async update(
    routeId: string,
    payload: UpdateRoutePayload,
    user: AuthenticatedUser,
  ): Promise<RouteDetailDTO> {
    const route = await this.loadRouteContext(routeId);
    await this.assertAuthor(route, user);

    if (route.status === 'archived_dismantled') {
      throw new DomainException(
        'ROUTE_ALREADY_DISMANTLED',
        'La ruta está desmantelada: su diseño ya no se edita.',
      );
    }

    if (payload.targetGradeId) {
      await this.grades.assertGradeBelongsToWallSystem(payload.targetGradeId, {
        id: route.wall_id,
        gym_id: route.gym_id,
        default_grade_system_id: route.default_grade_system_id,
      });
    }
    if (payload.placedHolds) this.assertNoDuplicateHolds(payload.placedHolds);

    await this.db.transaction().execute(async (trx) => {
      const patch = {
        ...(payload.title !== undefined ? { title: payload.title } : {}),
        ...(payload.targetGradeId !== undefined
          ? { target_grade_id: payload.targetGradeId }
          : {}),
        ...(payload.status !== undefined ? { status: payload.status } : {}),
      };
      if (Object.keys(patch).length > 0) {
        await trx.updateTable('routes').set(patch).where('id', '=', routeId).execute();
      }

      if (payload.placedHolds) {
        // Orden obligatorio (migración 007): primero el DELETE — que libera las
        // presas salientes vía trigger — y sólo después el INSERT. Al revés, una
        // presa que permanece chocaría contra unique_hold_per_active_route.
        await trx.deleteFrom('placed_holds').where('route_id', '=', routeId).execute();
        await this.lockAndVerifyHolds(trx, payload.placedHolds, route.gym_id);
        await this.insertPlacements(trx, routeId, payload.placedHolds);
      }

      await this.recalculateGrade(trx, routeId, route.wall_incline_deg, {
        gym_id: route.gym_id,
        default_grade_system_id: route.default_grade_system_id,
      });
    });

    return this.findDetail(routeId);
  }

  /** Algoritmo de 04 §2.9.2. */
  async dismantle(routeId: string, user: AuthenticatedUser): Promise<RouteDetailDTO> {
    const route = await this.loadRouteContext(routeId);
    await this.assertAuthor(route, user);

    if (route.status === 'archived_dismantled') {
      throw new DomainException('ROUTE_ALREADY_DISMANTLED', 'La ruta ya está desmantelada.');
    }

    // El trigger devuelve las presas a 'available' y sella dismantled_at.
    // El servicio NO escribe esas columnas.
    await this.db
      .updateTable('routes')
      .set({ status: 'archived_dismantled' })
      .where('id', '=', routeId)
      .execute();

    return this.findDetail(routeId);
  }

  /** Escala aplicable al muro, para el motor de dificultad. */
  async scaleForWall(wall: {
    gym_id: string;
    default_grade_system_id: string | null;
  }): Promise<GradeValueDTO[]> {
    if (wall.default_grade_system_id) {
      return this.grades.findValues(wall.default_grade_system_id);
    }
    const systems = await this.grades.findSystems(wall.gym_id);
    return systems.flatMap((s) => s.values);
  }

  // ---------------------------------------------------------------------------

  private async assertAuthorizedMember(user: AuthenticatedUser, gymId: string): Promise<void> {
    if (user.role === 'admin') return;
    if (user.memberships.some((m) => m.gymId === gymId)) return;
    if (await this.memberships.isAuthorizedMember(user.id, gymId)) return;
    throw new DomainException('NOT_GYM_MEMBER', 'No eres miembro autorizado de este boulder.');
  }

  private async assertAuthor(
    route: { creator_id: string; gym_id: string },
    user: AuthenticatedUser,
  ): Promise<void> {
    if (user.role === 'admin') return;
    if (route.creator_id === user.id) return;
    if (await this.memberships.isAdmin(user.id, route.gym_id)) return;
    throw new DomainException('NOT_ROUTE_AUTHOR', 'Sólo el autor del bloque puede modificarlo.');
  }

  private assertNoDuplicateHolds(placements: PlacedHoldDTO[]): void {
    const ids = new Set(placements.map((p) => p.holdId));
    if (ids.size !== placements.length) {
      throw new DomainException(
        'DUPLICATE_HOLD_IN_ROUTE',
        'La misma presa aparece dos veces en el bloque.',
      );
    }
  }

  /**
   * Paso 3 de 04 §2.9.1: bloqueo pesimista + verificación de disponibilidad y
   * pertenencia al gym del muro.
   */
  private async lockAndVerifyHolds(
    trx: Transaction<Database>,
    placements: PlacedHoldDTO[],
    gymId: string,
  ): Promise<void> {
    const holdIds = placements.map((p) => p.holdId);

    const rows = await trx
      .selectFrom('holds as h')
      .innerJoin('hold_sets as hs', 'hs.id', 'h.set_id')
      .select(['h.id', 'h.status', 'hs.gym_id'])
      .where('h.id', 'in', holdIds)
      .forUpdate()
      .execute();

    if (rows.length !== holdIds.length) throw notFound('Alguna presa del bloque');

    for (const row of rows) {
      if (row.gym_id !== gymId) {
        throw new DomainException(
          'VALIDATION_FAILED',
          'Alguna presa pertenece al inventario de otro boulder.',
        );
      }
      if (row.status !== 'available') {
        throw new DomainException(
          'HOLD_NOT_AVAILABLE',
          `La presa ${row.id} no está disponible (estado: ${row.status}).`,
        );
      }
    }
  }

  private async insertPlacements(
    trx: Transaction<Database>,
    routeId: string,
    placements: PlacedHoldDTO[],
  ): Promise<void> {
    await trx
      .insertInto('placed_holds')
      .values(
        placements.map((p) => ({
          route_id: routeId,
          hold_id: p.holdId,
          x_percent: p.xPercent,
          y_percent: p.yPercent,
          rotation_deg: p.rotationDeg,
          hold_role: p.role,
        })),
      )
      .execute();
  }

  /** Paso 6: sugerencia de `calculated_grade_id` (04 §6). */
  private async recalculateGrade(
    trx: Transaction<Database>,
    routeId: string,
    wallInclineDeg: number,
    wall: { gym_id: string; default_grade_system_id: string | null },
  ): Promise<void> {
    const rows = await trx
      .selectFrom('placed_holds as ph')
      .innerJoin('holds as h', 'h.id', 'ph.hold_id')
      .select(['ph.x_percent', 'ph.y_percent', 'ph.hold_role', 'h.difficulty_rating_weight'])
      .where('ph.route_id', '=', routeId)
      .execute();

    const placements: WeightedPlacement[] = rows.map((r) => ({
      xPercent: r.x_percent,
      yPercent: r.y_percent,
      role: r.hold_role as HoldRoleEnum,
      difficultyRatingWeight: r.difficulty_rating_weight,
    }));

    const scale = await this.scaleForWall(wall);
    const { grade } = this.difficulty.calculate(placements, wallInclineDeg, scale);

    await trx
      .updateTable('routes')
      .set({ calculated_grade_id: grade?.id ?? null })
      .where('id', '=', routeId)
      .execute();
  }

  private async loadRouteContext(routeId: string) {
    const row = await this.db
      .selectFrom('routes as r')
      .innerJoin('walls as w', 'w.id', 'r.wall_id')
      .select([
        'r.id',
        'r.creator_id',
        'r.status',
        'r.wall_id',
        'r.wall_incline_deg',
        'w.gym_id',
        'w.default_grade_system_id',
      ])
      .where('r.id', '=', routeId)
      .executeTakeFirst();
    if (!row) throw notFound('La ruta');
    return row;
  }

  private summaryQuery() {
    return this.db
      .selectFrom('routes as r')
      .innerJoin('users as u', 'u.id', 'r.creator_id')
      .innerJoin('grade_values as tg', 'tg.id', 'r.target_grade_id')
      .leftJoin('grade_values as cg', 'cg.id', 'r.calculated_grade_id')
      .select((eb) => [
        'r.id',
        'r.wall_id',
        'r.title',
        'r.status',
        'r.wall_incline_deg',
        'r.created_at',
        'r.dismantled_at',
        'u.id as creator_user_id',
        'u.username as creator_username',
        'u.avatar_url as creator_avatar_url',
        'tg.id as tg_id',
        'tg.system_id as tg_system_id',
        'tg.level_label as tg_level_label',
        'tg.rank_ordinal as tg_rank_ordinal',
        'tg.weight_factor as tg_weight_factor',
        'cg.id as cg_id',
        'cg.system_id as cg_system_id',
        'cg.level_label as cg_level_label',
        'cg.rank_ordinal as cg_rank_ordinal',
        'cg.weight_factor as cg_weight_factor',
        eb
          .selectFrom('placed_holds as ph')
          .select(sql<number>`count(*)::int`.as('c'))
          .whereRef('ph.route_id', '=', 'r.id')
          .as('holds_count'),
      ]);
  }

  private static toSummary(row: {
    id: string;
    wall_id: string;
    title: string;
    status: RouteStatusEnum;
    wall_incline_deg: number;
    created_at: Date;
    dismantled_at: Date | null;
    creator_user_id: string;
    creator_username: string;
    creator_avatar_url: string | null;
    tg_id: string;
    tg_system_id: string;
    tg_level_label: string;
    tg_rank_ordinal: number;
    tg_weight_factor: number;
    cg_id: string | null;
    cg_system_id: string | null;
    cg_level_label: string | null;
    cg_rank_ordinal: number | null;
    cg_weight_factor: number | null;
    holds_count: number | null;
  }): RouteSummaryDTO {
    return {
      id: row.id,
      wallId: row.wall_id,
      title: row.title,
      status: row.status,
      wallInclineDeg: row.wall_incline_deg,
      targetGrade: {
        id: row.tg_id,
        systemId: row.tg_system_id,
        levelLabel: row.tg_level_label,
        rankOrdinal: row.tg_rank_ordinal,
        weightFactor: row.tg_weight_factor,
      },
      ...(row.cg_id
        ? {
            calculatedGrade: {
              id: row.cg_id,
              systemId: row.cg_system_id as string,
              levelLabel: row.cg_level_label as string,
              rankOrdinal: row.cg_rank_ordinal as number,
              weightFactor: row.cg_weight_factor as number,
            },
          }
        : {}),
      // US-07: la autoría es visible en el catálogo.
      creator: {
        id: row.creator_user_id,
        username: row.creator_username,
        ...(row.creator_avatar_url ? { avatarUrl: row.creator_avatar_url } : {}),
      },
      holdsCount: row.holds_count ?? 0,
      createdAt: row.created_at.toISOString(),
      ...(row.dismantled_at ? { dismantledAt: row.dismantled_at.toISOString() } : {}),
    };
  }
}
