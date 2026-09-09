import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { GymsService } from './gyms.service';
import { GymAdminGuard } from '../auth/guards/gym-admin.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import { CreateGymPayload, UpdateGymPayload, type BoulderGymDTO } from './dto/gym.dto';

/** 04 §2.4 — Módulo Boulder Gyms (RF-1.1, RF-1.2) */
@Controller('gyms')
export class GymsController {
  constructor(private readonly gyms: GymsService) {}

  /**
   * El creador queda como admin autorizado del boulder. Su access token vigente
   * aún no lo refleja; los guards lo resuelven contra la BD (MembershipService)
   * y el claim aparece en el siguiente /auth/refresh.
   */
  @Post()
  create(
    @Body() body: CreateGymPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<BoulderGymDTO> {
    return this.gyms.create(body, user.id);
  }

  @Public()
  @Get()
  findAll(
    @Query('city') city?: string,
    @Query('country') country?: string,
    @Query('q') q?: string,
  ): Promise<BoulderGymDTO[]> {
    return this.gyms.findAll({ city, country, q });
  }

  @Public()
  @Get(':gymId')
  findOne(@Param('gymId', ParseUUIDPipe) gymId: string): Promise<BoulderGymDTO> {
    return this.gyms.findOne(gymId);
  }

  @UseGuards(GymAdminGuard)
  @Patch(':gymId')
  update(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Body() body: UpdateGymPayload,
  ): Promise<BoulderGymDTO> {
    return this.gyms.update(gymId, body);
  }
}
