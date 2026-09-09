import { Inject, Injectable } from '@nestjs/common';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException } from '../common/errors/domain.exception';
import { isMemberOf, type AuthenticatedUser } from './jwt-payload';
import type { MembershipStatusEnum } from '../database/schema';

export interface ResolvedMembership {
  status: MembershipStatusEnum;
  isGymAdmin: boolean;
}

/**
 * Resuelve la membresía real contra PostgreSQL.
 *
 * Los guards consultan primero los claims del JWT (§4.1, RNF-3: cero SELECT en
 * el camino feliz) y sólo caen aquí cuando el claim NO concede el permiso.
 * Esa asimetría es deliberada:
 *   - una membresía recién creada (POST /gyms, alta directa por admin) funciona
 *     sin esperar a la renovación del access token;
 *   - una membresía revocada nunca se re-concede, porque la BD manda en el
 *     camino de respaldo.
 * El coste es un SELECT indexado únicamente en peticiones que iban a fallar.
 */
@Injectable()
export class MembershipService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  async resolve(userId: string, gymId: string): Promise<ResolvedMembership | null> {
    const row = await this.db
      .selectFrom('gym_setters')
      .select(['status', 'is_gym_admin'])
      .where('user_id', '=', userId)
      .where('gym_id', '=', gymId)
      .executeTakeFirst();

    return row ? { status: row.status, isGymAdmin: row.is_gym_admin } : null;
  }

  async isAuthorizedMember(userId: string, gymId: string): Promise<boolean> {
    return (await this.resolve(userId, gymId))?.status === 'authorized';
  }

  async isAdmin(userId: string, gymId: string): Promise<boolean> {
    const m = await this.resolve(userId, gymId);
    return m?.status === 'authorized' && m.isGymAdmin;
  }

  /**
   * Misma regla que GymMemberGuard, para las rutas que no exponen `:gymId` en
   * la URL y tienen que resolver el boulder dueño del recurso.
   */
  async assertAuthorizedMember(user: AuthenticatedUser, gymId: string): Promise<void> {
    if (user.role === 'admin') return;
    if (isMemberOf(user, gymId)) return;
    if (await this.isAuthorizedMember(user.id, gymId)) return;
    throw new DomainException('NOT_GYM_MEMBER', 'No eres miembro autorizado de este boulder.');
  }
}
