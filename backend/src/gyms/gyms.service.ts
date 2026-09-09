import { Inject, Injectable } from '@nestjs/common';
import { KYSELY, type Db } from '../database/database.module';
import { notFound } from '../common/errors/domain.exception';
import type { BoulderGymDTO, CreateGymPayload, UpdateGymPayload } from './dto/gym.dto';
import type { BoulderGymsTable } from '../database/schema';
import type { Selectable } from 'kysely';

export interface GymFilters {
  city?: string;
  country?: string;
  q?: string;
}

@Injectable()
export class GymsService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  /** 04 §2.4: el creador queda `authorized` + `is_gym_admin` en el mismo commit. */
  async create(payload: CreateGymPayload, creatorId: string): Promise<BoulderGymDTO> {
    return this.db.transaction().execute(async (trx) => {
      const gym = await trx
        .insertInto('boulder_gyms')
        .values({
          name: payload.name,
          address: payload.address,
          city: payload.city,
          country: payload.country,
          phone: payload.phone ?? null,
          email: payload.email ?? null,
          pricing_plans: JSON.stringify(payload.pricingPlans ?? {}) as never,
          logo_url: payload.logoUrl ?? null,
        })
        .returningAll()
        .executeTakeFirstOrThrow();

      await trx
        .insertInto('gym_setters')
        .values({
          gym_id: gym.id,
          user_id: creatorId,
          status: 'authorized',
          is_gym_admin: true,
          authorized_by: creatorId,
          authorized_at: new Date(),
        })
        .execute();

      return GymsService.toDTO(gym);
    });
  }

  async findAll(filters: GymFilters): Promise<BoulderGymDTO[]> {
    let query = this.db.selectFrom('boulder_gyms').selectAll();

    if (filters.city) query = query.where('city', 'ilike', filters.city);
    if (filters.country) query = query.where('country', 'ilike', filters.country);
    if (filters.q) query = query.where('name', 'ilike', `%${filters.q}%`);

    const rows = await query.orderBy('name').execute();
    return rows.map(GymsService.toDTO);
  }

  async findOne(gymId: string): Promise<BoulderGymDTO> {
    const row = await this.db
      .selectFrom('boulder_gyms')
      .selectAll()
      .where('id', '=', gymId)
      .executeTakeFirst();
    if (!row) throw notFound('El boulder');
    return GymsService.toDTO(row);
  }

  async update(gymId: string, payload: UpdateGymPayload): Promise<BoulderGymDTO> {
    const patch = {
      ...(payload.name !== undefined ? { name: payload.name } : {}),
      ...(payload.address !== undefined ? { address: payload.address } : {}),
      ...(payload.city !== undefined ? { city: payload.city } : {}),
      ...(payload.country !== undefined ? { country: payload.country } : {}),
      ...(payload.phone !== undefined ? { phone: payload.phone } : {}),
      ...(payload.email !== undefined ? { email: payload.email } : {}),
      ...(payload.pricingPlans !== undefined
        ? { pricing_plans: JSON.stringify(payload.pricingPlans) as never }
        : {}),
      ...(payload.logoUrl !== undefined ? { logo_url: payload.logoUrl } : {}),
    };

    if (Object.keys(patch).length === 0) return this.findOne(gymId);

    const row = await this.db
      .updateTable('boulder_gyms')
      .set({ ...patch, updated_at: new Date() })
      .where('id', '=', gymId)
      .returningAll()
      .executeTakeFirst();
    if (!row) throw notFound('El boulder');
    return GymsService.toDTO(row);
  }

  /** Mapeo snake_case -> camelCase (04 §3). */
  static toDTO(row: Selectable<BoulderGymsTable>): BoulderGymDTO {
    return {
      id: row.id,
      name: row.name,
      address: row.address,
      city: row.city,
      country: row.country,
      ...(row.phone ? { phone: row.phone } : {}),
      ...(row.email ? { email: row.email } : {}),
      pricingPlans: (row.pricing_plans ?? {}) as Record<string, unknown>,
      ...(row.logo_url ? { logoUrl: row.logo_url } : {}),
    };
  }
}
