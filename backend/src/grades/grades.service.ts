import { Inject, Injectable } from '@nestjs/common';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException, notFound } from '../common/errors/domain.exception';
import type {
  CreateGradeSystemPayload,
  GradeSystemDTO,
  GradeValueDTO,
} from './dto/grade.dto';

@Injectable()
export class GradesService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  /** Sistemas globales (`gym_id IS NULL`) + los del gym indicado (04 §2.6). */
  async findSystems(gymId?: string): Promise<GradeSystemDTO[]> {
    let query = this.db.selectFrom('grade_systems').selectAll().where('is_active', '=', true);

    query = gymId
      ? query.where((eb) => eb.or([eb('gym_id', 'is', null), eb('gym_id', '=', gymId)]))
      : query.where('gym_id', 'is', null);

    const systems = await query.orderBy('name').execute();
    if (systems.length === 0) return [];

    const values = await this.db
      .selectFrom('grade_values')
      .selectAll()
      .where(
        'system_id',
        'in',
        systems.map((s) => s.id),
      )
      .orderBy('rank_ordinal', 'asc')
      .execute();

    return systems.map((s) => ({
      id: s.id,
      ...(s.gym_id ? { gymId: s.gym_id } : {}),
      name: s.name,
      ...(s.description ? { description: s.description } : {}),
      values: values
        .filter((v) => v.system_id === s.id)
        .map(GradesService.toValueDTO),
    }));
  }

  /** 04 §2.6: ordenado por `rank_ordinal` ASC. */
  async findValues(systemId: string): Promise<GradeValueDTO[]> {
    const system = await this.db
      .selectFrom('grade_systems')
      .select('id')
      .where('id', '=', systemId)
      .executeTakeFirst();
    if (!system) throw notFound('El sistema de grados');

    const rows = await this.db
      .selectFrom('grade_values')
      .selectAll()
      .where('system_id', '=', systemId)
      .orderBy('rank_ordinal', 'asc')
      .execute();

    return rows.map(GradesService.toValueDTO);
  }

  /** Escala personalizada propiedad de un boulder (RF-3.2). */
  async createSystem(gymId: string, payload: CreateGradeSystemPayload): Promise<GradeSystemDTO> {
    const ordinals = new Set(payload.values.map((v) => v.rankOrdinal));
    if (ordinals.size !== payload.values.length) {
      throw new DomainException('VALIDATION_FAILED', 'Los `rankOrdinal` deben ser únicos.');
    }
    const labels = new Set(payload.values.map((v) => v.levelLabel));
    if (labels.size !== payload.values.length) {
      throw new DomainException('VALIDATION_FAILED', 'Los `levelLabel` deben ser únicos.');
    }

    const systemId = await this.db.transaction().execute(async (trx) => {
      const system = await trx
        .insertInto('grade_systems')
        .values({
          gym_id: gymId,
          name: payload.name,
          description: payload.description ?? null,
        })
        .returning('id')
        .executeTakeFirstOrThrow();

      await trx
        .insertInto('grade_values')
        .values(
          payload.values.map((v) => ({
            system_id: system.id,
            level_label: v.levelLabel,
            rank_ordinal: v.rankOrdinal,
            weight_factor: v.weightFactor,
          })),
        )
        .execute();

      return system.id;
    });

    const [system] = (await this.findSystems(gymId)).filter((s) => s.id === systemId);
    return system;
  }

  /**
   * Resuelve el sistema de grados aplicable a un muro y valida pertenencia.
   *
   * Hueco cerrado: 04 §2.9.1 exige que `target_grade_id` pertenezca "al sistema
   * del muro", pero `walls.default_grade_system_id` es NULLABLE. Regla adoptada:
   *   - muro CON sistema por defecto -> el grado debe ser de ese sistema;
   *   - muro SIN sistema por defecto -> se acepta cualquier grado de un sistema
   *     global o del propio gym del muro; nunca la escala privada de otro gym.
   */
  async assertGradeBelongsToWallSystem(
    gradeId: string,
    wall: { id: string; gym_id: string; default_grade_system_id: string | null },
  ): Promise<void> {
    const grade = await this.db
      .selectFrom('grade_values as gv')
      .innerJoin('grade_systems as gs', 'gs.id', 'gv.system_id')
      .select(['gv.id', 'gv.system_id', 'gs.gym_id as system_gym_id'])
      .where('gv.id', '=', gradeId)
      .executeTakeFirst();

    if (!grade) throw notFound('El grado indicado');

    if (wall.default_grade_system_id) {
      if (grade.system_id !== wall.default_grade_system_id) {
        throw new DomainException(
          'GRADE_SYSTEM_MISMATCH',
          'El grado no pertenece al sistema de grados configurado para el muro.',
        );
      }
      return;
    }

    if (grade.system_gym_id !== null && grade.system_gym_id !== wall.gym_id) {
      throw new DomainException(
        'GRADE_SYSTEM_MISMATCH',
        'El grado pertenece a una escala privada de otro boulder.',
      );
    }
  }

  static toValueDTO(row: {
    id: string;
    system_id: string;
    level_label: string;
    rank_ordinal: number;
    weight_factor: number;
  }): GradeValueDTO {
    return {
      id: row.id,
      systemId: row.system_id,
      levelLabel: row.level_label,
      rankOrdinal: row.rank_ordinal,
      weightFactor: row.weight_factor,
    };
  }
}
