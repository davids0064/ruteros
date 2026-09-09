import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';

export const UPLOAD_SCOPES = ['hold_crop', 'wall_photo', 'gym_logo', 'user_avatar'] as const;
export type UploadScope = (typeof UPLOAD_SCOPES)[number];

/** 04 §2.10 */
export class PresignRequest {
  @IsIn(UPLOAD_SCOPES) scope!: UploadScope;
  @IsIn(['image/png', 'image/jpeg']) contentType!: 'image/png' | 'image/jpeg';

  /** Un lote de presas en una sola llamada (KPI: 10 presas < 15 s). */
  @IsOptional() @IsInt() @Min(1) @Max(50) count?: number;
}

export interface PresignResponse {
  uploads: Array<{ uploadUrl: string; publicUrl: string; objectKey: string }>;
  /**
   * Tope por objeto (`S3_MAX_OBJECT_BYTES`). Viaja en la respuesta porque la
   * URL prefirmada ya no puede exigirlo: el cliente descarta o recomprime
   * antes de subir.
   */
  maxObjectBytes: number;
}
