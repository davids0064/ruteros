import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

/** 04 §2.6 */
export class GradeValueInput {
  @IsString() @MinLength(1) @MaxLength(20) levelLabel!: string;
  @IsInt() @Min(0) rankOrdinal!: number;
  @IsNumber() @IsPositive() weightFactor!: number;
}

export class CreateGradeSystemPayload {
  @IsString() @MinLength(2) @MaxLength(100) name!: string;
  @IsOptional() @IsString() description?: string;

  @IsArray()
  @ArrayMinSize(2, { message: 'Un sistema de grados necesita al menos dos niveles.' })
  @ValidateNested({ each: true })
  @Type(() => GradeValueInput)
  values!: GradeValueInput[];
}

export interface GradeValueDTO {
  id: string;
  systemId: string;
  levelLabel: string;
  rankOrdinal: number;
  weightFactor: number;
}

export interface GradeSystemDTO {
  id: string;
  gymId?: string; // ausente => sistema global
  name: string;
  description?: string;
  values: GradeValueDTO[];
}
