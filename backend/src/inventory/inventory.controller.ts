import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { GymMemberGuard } from '../auth/guards/gym-member.guard';
import { MembershipService } from '../auth/membership.service';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import type { HoldStatusEnum } from '../database/schema';
import {
  CreateHoldBatchPayload,
  CreateHoldSetPayload,
  UpdateHoldPayload,
  type HoldDTO,
  type HoldSetDTO,
} from './dto/inventory.dto';

/** 04 §2.8 — Inventario */
@Controller()
export class InventoryController {
  constructor(
    private readonly inventory: InventoryService,
    private readonly memberships: MembershipService,
  ) {}

  @UseGuards(GymMemberGuard)
  @Post('gyms/:gymId/hold-sets')
  createSet(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Body() body: CreateHoldSetPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<HoldSetDTO> {
    return this.inventory.createSet(gymId, body, user.id);
  }

  @UseGuards(GymMemberGuard)
  @Get('gyms/:gymId/hold-sets')
  findSets(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Query('colorHex') colorHex?: string,
  ): Promise<HoldSetDTO[]> {
    return this.inventory.findSetsByGym(gymId, colorHex);
  }

  /** Transaccional: o entran las N presas del set segmentado, o ninguna. */
  @Post('hold-sets/:setId/holds/batch')
  async createHolds(
    @Param('setId', ParseUUIDPipe) setId: string,
    @Body() body: CreateHoldBatchPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<HoldDTO[]> {
    await this.assertMemberOfSetGym(setId, user);
    return this.inventory.createHoldsBatch(setId, body);
  }

  @Get('hold-sets/:setId/holds')
  async findHolds(
    @Param('setId', ParseUUIDPipe) setId: string,
    @CurrentUser() user: AuthenticatedUser,
    @Query('status') status?: HoldStatusEnum,
  ): Promise<HoldDTO[]> {
    await this.assertMemberOfSetGym(setId, user);
    return this.inventory.findHoldsBySet(setId, status);
  }

  /** RNF-3: < 500 ms. Alimenta el editor de canvas. */
  @UseGuards(GymMemberGuard)
  @Get('gyms/:gymId/holds/available')
  findAvailable(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Query('setIds') setIds?: string,
  ): Promise<HoldDTO[]> {
    const ids = setIds
      ? setIds.split(',').map((s) => s.trim()).filter(Boolean)
      : undefined;
    return this.inventory.findAvailableByGym(gymId, ids);
  }

  @Patch('holds/:holdId')
  async updateHold(
    @Param('holdId', ParseUUIDPipe) holdId: string,
    @Body() body: UpdateHoldPayload,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<HoldDTO> {
    const gymId = await this.inventory.getHoldGymId(holdId);
    await this.memberships.assertAuthorizedMember(user, gymId);
    return this.inventory.updateHold(holdId, body);
  }

  /**
   * Las rutas anidadas bajo `:setId` no exponen `:gymId`: hay que resolver el
   * boulder dueño del set antes de comprobar la membresía.
   */
  private async assertMemberOfSetGym(setId: string, user: AuthenticatedUser): Promise<void> {
    await this.memberships.assertAuthorizedMember(
      user,
      await this.inventory.getSetGymId(setId),
    );
  }
}
