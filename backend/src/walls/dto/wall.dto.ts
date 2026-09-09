import { PartialType } from '@nestjs/mapped-types';
import {
  IsBoolean,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  IsUrl,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

/** 04 §2.7 */
export class CreateWallPayload {
  @IsString() @MinLength(2) @MaxLength(100) name!: string;

  /** Devuelta por POST /uploads/presign (04 §5). */
  @IsUrl({ require_tld: false }) photoUrl!: string;

  @IsNumber() @IsPositive() widthCm!: number;
  @IsNumber() @IsPositive() heightCm!: number;

  /** theta leído del giroscopio (RF-3.1). */
  @IsNumber() @Min(-90) @Max(90) defaultInclineDeg!: number;

  @IsOptional() @IsUUID() defaultGradeSystemId?: string;
  @IsOptional() @IsBoolean() isPublic?: boolean;
}

export class UpdateWallPayload extends PartialType(CreateWallPayload) {}

export interface WallDTO {
  id: string;
  gymId: string;
  creatorId?: string;
  name: string;
  photoUrl: string;
  widthCm: number;
  heightCm: number;
  defaultInclineDeg: number;
  defaultGradeSystemId?: string;
  isPublic: boolean;
  activeRoutesCount: number;
}
