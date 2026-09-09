import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import type { HoldRoleEnum, RouteStatusEnum } from '../../database/schema';
import type { GradeValueDTO } from '../../grades/dto/grade.dto';
import type { HoldDTO } from '../../inventory/dto/inventory.dto';

export const HOLD_ROLES: HoldRoleEnum[] = ['start', 'hand', 'foot_only', 'top'];

/** `PlacedHoldDTO` de 03_DATA_MODELS.md, sin alteraciones. */
export class PlacedHoldDTO {
  @IsOptional() @IsUUID() id?: string;
  @IsUUID() holdId!: string;

  @IsNumber() @Min(0) @Max(100) xPercent!: number;
  @IsNumber() @Min(0) @Max(100) yPercent!: number;

  @IsInt() @Min(0) @Max(359) rotationDeg!: number;

  /** 04 §3: `hold_role` se serializa como `role`, NO como `holdRole`. */
  @IsIn(HOLD_ROLES) role!: HoldRoleEnum;
}

/** `RouteCreatePayload` de 03_DATA_MODELS.md, sin alteraciones. */
export class RouteCreatePayload {
  @IsUUID() wallId!: string;

  /** Viaja por contrato, pero el servidor usa el `sub` del JWT (04 §2.9). */
  @IsUUID() creatorId!: string;

  @IsString() @MinLength(1) @MaxLength(100) title!: string;
  @IsUUID() targetGradeId!: string;

  @IsNumber() @Min(-90) @Max(90) wallInclineDeg!: number;

  @IsArray()
  @ArrayMinSize(2, { message: 'Un bloque necesita al menos dos presas.' })
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => PlacedHoldDTO)
  placedHolds!: PlacedHoldDTO[];
}

export class UpdateRoutePayload {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(100) title?: string;
  @IsOptional() @IsUUID() targetGradeId?: string;

  /** 'archived_dismantled' sólo vía POST /routes/:id/dismantle. */
  @IsOptional() @IsIn(['draft', 'active']) status?: 'draft' | 'active';

  /** Reemplazo total del set. */
  @IsOptional()
  @IsArray()
  @ArrayMinSize(2)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => PlacedHoldDTO)
  placedHolds?: PlacedHoldDTO[];
}

/** 04 §2.9 — RF-4.1: filtros que elige el setter. */
export class GenerateRouteRequest {
  @IsUUID() wallId!: string;
  @IsUUID() gradeSystemId!: string;
  @IsUUID() targetGradeId!: string;

  @IsNumber() @Min(-90) @Max(90) wallInclineDeg!: number;

  @IsArray()
  @ArrayMinSize(1, { message: 'Habilita al menos un set de presas.' })
  @IsUUID('4', { each: true })
  enabledSetIds!: string[];

  @IsOptional() @IsInt() @Min(2) @Max(30) holdCount?: number;
}

export interface GenerateRouteProposal {
  placedHolds: PlacedHoldDTO[]; // sin `id`: aún no persistidas
  estimatedGradeId: string;
  rationale: string;
}

export interface RouteSummaryDTO {
  id: string;
  wallId: string;
  title: string;
  status: RouteStatusEnum;
  wallInclineDeg: number;
  targetGrade: GradeValueDTO;
  calculatedGrade?: GradeValueDTO;
  creator: { id: string; username: string; avatarUrl?: string };
  holdsCount: number;
  createdAt: string;
  dismantledAt?: string;
}

export interface RouteDetailDTO extends RouteSummaryDTO {
  placedHolds: Array<PlacedHoldDTO & { hold: HoldDTO }>;
}
