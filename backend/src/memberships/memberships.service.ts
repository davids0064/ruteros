import { Inject, Injectable } from '@nestjs/common';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException, notFound } from '../common/errors/domain.exception';
import { MembershipService } from '../auth/membership.service';
import type { MembershipStatusEnum } from '../database/schema';
import type {
  CreateMembershipPayload,
  GymSetterDTO,
  UpdateMembershipPayload,
} from './dto/membership.dto';

@Injectable()
export class MembershipsService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly memberships: MembershipService,
  ) {}

  /**
   * 04 §2.5:
   *   sin `userId` -> autopostulación del solicitante, queda 'pending';
   *   con `userId` -> alta directa, exige ser admin del gym, queda 'authorized'.
   */
  async create(
    gymId: string,
    payload: CreateMembershipPayload,
    requesterId: string,
    requesterIsPlatformAdmin: boolean,
  ): Promise<GymSetterDTO> {
    const gym = await this.db
      .selectFrom('boulder_gyms')
      .select('id')
      .where('id', '=', gymId)
      .executeTakeFirst();
    if (!gym) throw notFound('El boulder');

    const isDirectGrant = payload.userId !== undefined && payload.userId !== requesterId;

    if (isDirectGrant) {
      const allowed =
        requesterIsPlatformAdmin || (await this.memberships.isAdmin(requesterId, gymId));
      if (!allowed) {
        throw new DomainException(
          'NOT_GYM_ADMIN',
          'Sólo un administrador del boulder puede dar de alta a otro setter.',
        );
      }
    }

    const targetUserId = payload.userId ?? requesterId;
    const status: MembershipStatusEnum = isDirectGrant ? 'authorized' : 'pending';

    const row = await this.db
      .insertInto('gym_setters')
      .values({
        gym_id: gymId,
        user_id: targetUserId,
        status,
        is_gym_admin: false,
        authorized_by: isDirectGrant ? requesterId : null,
        authorized_at: isDirectGrant ? new Date() : null,
      })
      .returning('id')
      .executeTakeFirstOrThrow();

    return this.findOne(gymId, row.id);
  }

  async findAll(gymId: string, status?: MembershipStatusEnum): Promise<GymSetterDTO[]> {
    let query = this.baseQuery().where('gs.gym_id', '=', gymId);
    if (status) query = query.where('gs.status', '=', status);
    const rows = await query.orderBy('u.username').execute();
    return rows.map(MembershipsService.toDTO);
  }

  async findOne(gymId: string, setterId: string): Promise<GymSetterDTO> {
    const row = await this.baseQuery()
      .where('gs.gym_id', '=', gymId)
      .where('gs.id', '=', setterId)
      .executeTakeFirst();
    if (!row) throw notFound('La membresía');
    return MembershipsService.toDTO(row);
  }

  /** Sella `authorized_by` / `authorized_at` al autorizar (04 §2.5). */
  async update(
    gymId: string,
    setterId: string,
    payload: UpdateMembershipPayload,
    actorId: string,
  ): Promise<GymSetterDTO> {
    const current = await this.findOne(gymId, setterId);

    const becomesAuthorized =
      payload.status === 'authorized' && current.status !== 'authorized';

    await this.db
      .updateTable('gym_setters')
      .set({
        ...(payload.status !== undefined ? { status: payload.status } : {}),
        ...(payload.isGymAdmin !== undefined ? { is_gym_admin: payload.isGymAdmin } : {}),
        ...(becomesAuthorized ? { authorized_by: actorId, authorized_at: new Date() } : {}),
      })
      .where('id', '=', setterId)
      .where('gym_id', '=', gymId)
      .execute();

    // El trigger de la migración 008 ya invalidó los refresh tokens del setter.
    return this.findOne(gymId, setterId);
  }

  private baseQuery() {
    return this.db
      .selectFrom('gym_setters as gs')
      .innerJoin('users as u', 'u.id', 'gs.user_id')
      .select([
        'gs.id',
        'gs.gym_id',
        'gs.user_id',
        'gs.status',
        'gs.is_gym_admin',
        'gs.authorized_by',
        'gs.authorized_at',
        'gs.created_at',
        'u.username',
        'u.display_name',
        'u.avatar_url',
      ]);
  }

  private static toDTO(row: {
    id: string;
    gym_id: string;
    user_id: string;
    status: MembershipStatusEnum;
    is_gym_admin: boolean;
    authorized_by: string | null;
    authorized_at: Date | null;
    created_at: Date;
    username: string;
    display_name: string | null;
    avatar_url: string | null;
  }): GymSetterDTO {
    return {
      id: row.id,
      gymId: row.gym_id,
      userId: row.user_id,
      username: row.username,
      ...(row.display_name ? { displayName: row.display_name } : {}),
      ...(row.avatar_url ? { avatarUrl: row.avatar_url } : {}),
      status: row.status,
      isGymAdmin: row.is_gym_admin,
      ...(row.authorized_by ? { authorizedBy: row.authorized_by } : {}),
      ...(row.authorized_at ? { authorizedAt: row.authorized_at.toISOString() } : {}),
      createdAt: row.created_at.toISOString(),
    };
  }
}
