import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { RoutesService } from './routes.service';
import { GeneratorService } from './generator.service';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import type { RouteStatusEnum } from '../database/schema';
import {
  GenerateRouteRequest,
  RouteCreatePayload,
  UpdateRoutePayload,
  type GenerateRouteProposal,
  type RouteDetailDTO,
  type RouteSummaryDTO,
} from './dto/route.dto';

/** 04 §2.9 — Rutas (RF-4.2, RF-4.3, US-05, US-07) */
@Controller()
export class RoutesController {
  constructor(
    private readonly routes: RoutesService,
    private readonly generator: GeneratorService,
  ) {}

  /** No persiste nada: propuesta en RAM (RF-4.1). */
  @Post('routes/generate')
  @HttpCode(200)
  generate(@Body() body: GenerateRouteRequest): Promise<GenerateRouteProposal> {
    return this.generator.generate(body);
  }

  @Post('routes')
  create(
    @Body() body: RouteCreatePayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<RouteDetailDTO> {
    return this.routes.create(body, user);
  }

  /** US-07: catálogo de bloques de un muro, con su autoría. */
  @Public()
  @Get('walls/:wallId/routes')
  findByWall(
    @Param('wallId', ParseUUIDPipe) wallId: string,
    @Query('status') status?: RouteStatusEnum,
    @Query('creatorId') creatorId?: string,
    @Query('gradeId') gradeId?: string,
  ): Promise<RouteSummaryDTO[]> {
    return this.routes.findByWall(wallId, { status, creatorId, gradeId });
  }

  @Public()
  @Get('routes/:routeId')
  findOne(@Param('routeId', ParseUUIDPipe) routeId: string): Promise<RouteDetailDTO> {
    return this.routes.findDetail(routeId);
  }

  @Patch('routes/:routeId')
  update(
    @Param('routeId', ParseUUIDPipe) routeId: string,
    @Body() body: UpdateRoutePayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<RouteDetailDTO> {
    return this.routes.update(routeId, body, user);
  }

  /** Libera las presas vía trigger (04 §2.9.2). */
  @Post('routes/:routeId/dismantle')
  @HttpCode(200)
  dismantle(
    @Param('routeId', ParseUUIDPipe) routeId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<RouteDetailDTO> {
    return this.routes.dismantle(routeId, user);
  }
}
