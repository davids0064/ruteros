import {
  IsEmail,
  IsObject,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
  MinLength,
} from 'class-validator';
import { PartialType } from '@nestjs/mapped-types';

/** 04 §2.4 */
export class CreateGymPayload {
  @IsString() @MinLength(2) @MaxLength(150) name!: string;
  @IsString() @MinLength(3) address!: string;
  @IsString() @MinLength(2) @MaxLength(100) city!: string;
  @IsString() @MinLength(2) @MaxLength(100) country!: string;

  @IsOptional() @IsString() @MaxLength(30) phone?: string;
  @IsOptional() @IsEmail() @MaxLength(255) email?: string;

  /** -> boulder_gyms.pricing_plans (JSONB). Estructura libre por diseño (RF-1.2). */
  @IsOptional() @IsObject() pricingPlans?: Record<string, unknown>;

  @IsOptional() @IsUrl({ require_tld: false }) logoUrl?: string;
}

/** `Partial<CreateGymPayload>` de 04 §2.4, con las mismas reglas de validación. */
export class UpdateGymPayload extends PartialType(CreateGymPayload) {}

/** Idéntico a BoulderGymDTO de 03_DATA_MODELS.md, sin alteraciones. */
export interface BoulderGymDTO {
  id: string;
  name: string;
  address: string;
  city: string;
  country: string;
  phone?: string;
  email?: string;
  pricingPlans: Record<string, unknown>;
  logoUrl?: string;
}
