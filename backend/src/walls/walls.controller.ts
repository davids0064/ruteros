import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { WallsService } from './walls.service';
import { GymMemberGuard } from '../auth/guards/gym-member.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { OptionalAuth, Public } from '../common/decorators/public.decorator';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import { CreateWallPayload, UpdateWallPayload, type WallDTO } from './dto/wall.dto';

/** 04 §2.7 — Muros (RF-3.1, US-03) */
@Controller()
export class WallsController {
  constructor(private readonly walls: WallsService) {}

  @UseGuards(GymMemberGuard)
  @Post('gyms/:gymId/walls')
  create(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Body() body: CreateWallPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<WallDTO> {
    return this.walls.create(gymId, body, user.id);
  }

  /** Sin sesión sólo se listan los muros públicos (US-03). */
  @OptionalAuth()
  @Get('gyms/:gymId/walls')
  findAll(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @CurrentUser() user: AuthenticatedUser | undefined,
  ): Promise<WallDTO[]> {
    return this.walls.findAllByGym(gymId, user);
  }

  @Public()
  @Get('walls/:wallId')
  findOne(@Param('wallId', ParseUUIDPipe) wallId: string): Promise<WallDTO> {
    return this.walls.findOne(wallId);
  }

  @Patch('walls/:wallId')
  update(
    @Param('wallId', ParseUUIDPipe) wallId: string,
    @Body() body: UpdateWallPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<WallDTO> {
    return this.walls.update(wallId, body, user);
  }
}
