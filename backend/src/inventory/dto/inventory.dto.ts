import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsPositive,
  IsString,
  IsUrl,
  Matches,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';
import type { HoldStatusEnum, HoldTypeEnum } from '../../database/schema';

export const HOLD_CATEGORIES: HoldTypeEnum[] = [
  'crimp',
  'sloper',
  'jug',
  'pinch',
  'foothold',
  'volume',
];

/** Estados que el cliente PUEDE fijar. `in_use` es potestad de los triggers (RF-2.3). */
export const CLIENT_SETTABLE_HOLD_STATUSES: HoldStatusEnum[] = [
  'available',
  'maintenance',
  'retired',
];

export class CreateHoldSetPayload {
  @IsString() @MinLength(2) @MaxLength(100) name!: string;

  @Matches(/^#[0-9A-Fa-f]{6}$/, { message: 'colorHex debe tener la forma #RRGGBB.' })
  colorHex!: string;
}

export class BoundingBoxData {
  @IsInt() @IsPositive() width_px!: number;
  @IsInt() @IsPositive() height_px!: number;
}

export class CreateHoldPayload {
  /** URL S3 del PNG con alpha, devuelta por POST /uploads/presign. */
  @IsUrl({ require_tld: false }) imageCropUrl!: string;

  @IsIn(HOLD_CATEGORIES) typeCategory!: HoldTypeEnum;

  @IsOptional() @IsNumber() @IsPositive() difficultyRatingWeight?: number;

  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => BoundingBoxData)
  boundingBoxData?: BoundingBoxData;
}

/** Alta masiva post-segmentación — transaccional (04 §2.8). */
export class CreateHoldBatchPayload {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => CreateHoldPayload)
  holds!: CreateHoldPayload[];
}

export class UpdateHoldPayload {
  @IsOptional() @IsIn(HOLD_CATEGORIES) typeCategory?: HoldTypeEnum;
  @IsOptional() @IsNumber() @IsPositive() difficultyRatingWeight?: number;

  /**
   * 04 §2.8: `in_use` NO es escribible por el cliente, ni directamente ni para
   * sacar una presa de ese estado. Lo rechaza el propio validador.
   */
  @IsOptional()
  @IsIn(CLIENT_SETTABLE_HOLD_STATUSES, {
    message: 'El estado `in_use` lo gobierna la base de datos, no la API.',
  })
  status?: HoldStatusEnum;
}

export interface HoldSetDTO {
  id: string;
  gymId: string;
  creatorId?: string;
  name: string;
  colorHex: string;
  holdsCount: number;
  availableCount: number;
}

export interface HoldDTO {
  id: string;
  setId: string;
  imageCropUrl: string;
  typeCategory: HoldTypeEnum;
  status: HoldStatusEnum;
  difficultyRatingWeight: number;
  boundingBoxData?: { width_px: number; height_px: number };
}
