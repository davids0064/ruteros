import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { MembershipsService } from './memberships.service';
import { GymAdminGuard } from '../auth/guards/gym-admin.guard';
import { GymMemberGuard } from '../auth/guards/gym-member.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import type { MembershipStatusEnum } from '../database/schema';
import {
  CreateMembershipPayload,
  UpdateMembershipPayload,
  type GymSetterDTO,
} from './dto/membership.dto';

/** 04 §2.5 — Membresías (US-01, US-04) */
@Controller('gyms/:gymId/setters')
export class MembershipsController {
  constructor(private readonly service: MembershipsService) {}

  /** Sin guard de gym: la autopostulación la hace, por definición, un no-miembro. */
  @Post()
  create(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Body() body: CreateMembershipPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<GymSetterDTO> {
    return this.service.create(gymId, body, user.id, user.role === 'admin');
  }

  @UseGuards(GymMemberGuard)
  @Get()
  findAll(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Query('status') status?: MembershipStatusEnum,
  ): Promise<GymSetterDTO[]> {
    return this.service.findAll(gymId, status);
  }

  @UseGuards(GymAdminGuard)
  @Patch(':setterId')
  update(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Param('setterId', ParseUUIDPipe) setterId: string,
    @Body() body: UpdateMembershipPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<GymSetterDTO> {
    return this.service.update(gymId, setterId, body, user.id);
  }
}
