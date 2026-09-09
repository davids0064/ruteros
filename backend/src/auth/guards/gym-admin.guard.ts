import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { DomainException } from '../../common/errors/domain.exception';
import { MembershipService } from '../membership.service';
import { isAdminOf, type AuthenticatedUser } from '../jwt-payload';

/** 04 §4.2: exige `isGymAdmin` sobre `:gymId`. */
@Injectable()
export class GymAdminGuard implements CanActivate {
  constructor(private readonly memberships: MembershipService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const user = req.user as AuthenticatedUser | undefined;
    const gymId: string = req.params.gymId;

    if (!user) throw new DomainException('UNAUTHENTICATED', 'Token ausente, expirado o inválido.');
    if (user.role === 'admin') return true;
    if (isAdminOf(user, gymId)) return true;
    if (await this.memberships.isAdmin(user.id, gymId)) return true;

    throw new DomainException('NOT_GYM_ADMIN', 'Se requiere ser administrador del boulder.');
  }
}
