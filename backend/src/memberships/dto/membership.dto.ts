import { IsBoolean, IsIn, IsOptional, IsUUID } from 'class-validator';
import type { MembershipStatusEnum } from '../../database/schema';

/** 04 §2.5 */
export class CreateMembershipPayload {
  /** Ausente = autopostulación (-> 'pending'). Presente = alta directa por admin. */
  @IsOptional() @IsUUID() userId?: string;
}

export class UpdateMembershipPayload {
  @IsOptional()
  @IsIn(['pending', 'authorized', 'revoked'])
  status?: MembershipStatusEnum;

  @IsOptional() @IsBoolean() isGymAdmin?: boolean;
}

export interface GymSetterDTO {
  id: string;
  gymId: string;
  userId: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
  status: MembershipStatusEnum;
  isGymAdmin: boolean;
  authorizedBy?: string;
  authorizedAt?: string;
  createdAt: string;
}
