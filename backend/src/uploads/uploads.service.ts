import { Inject, Injectable, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'node:crypto';
import { DomainException } from '../common/errors/domain.exception';
import type { PresignRequest, PresignResponse, UploadScope } from './dto/upload.dto';

export const S3_CLIENT = 'S3_CLIENT';

/**
 * Subida directa cliente -> S3 (04 §5). El backend nunca proxea binarios: es lo
 * que hace alcanzable el KPI de 10 presas en < 15 s.
 */
@Injectable()
export class UploadsService {
  private readonly bucket: string;
  private readonly publicBaseUrl: string;
  private readonly ttl: number;
  private readonly maxBytes: number;

  constructor(
    private readonly config: ConfigService,
    @Optional() @Inject(S3_CLIENT) private readonly s3?: S3Client,
  ) {
    this.bucket = config.get<string>('S3_BUCKET') ?? 'boulder-cosetter';
    this.publicBaseUrl =
      config.get<string>('S3_PUBLIC_BASE_URL') ??
      `https://${this.bucket}.s3.${config.get('S3_REGION') ?? 'us-east-1'}.amazonaws.com`;
    this.ttl = Number(config.get('S3_PRESIGN_TTL') ?? 300);
    this.maxBytes = Number(config.get('S3_MAX_OBJECT_BYTES') ?? 8 * 1024 * 1024);
  }

  /** `{scope}/{gymId}/{yyyy}/{MM}/{uuid}.{ext}` (04 §5). */
  buildObjectKey(scope: UploadScope, gymId: string, contentType: string): string {
    const now = new Date();
    const yyyy = now.getUTCFullYear();
    const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
    const ext = contentType === 'image/png' ? 'png' : 'jpg';
    return `${scope}/${gymId}/${yyyy}/${mm}/${randomUUID()}.${ext}`;
  }

  publicUrlFor(objectKey: string): string {
    return `${this.publicBaseUrl.replace(/\/$/, '')}/${objectKey}`;
  }

  async presign(request: PresignRequest, gymId: string): Promise<PresignResponse> {
    const count = request.count ?? 1;
    const uploads = [];

    for (let i = 0; i < count; i += 1) {
      const objectKey = this.buildObjectKey(request.scope, gymId, request.contentType);
      uploads.push({
        uploadUrl: await this.signPut(objectKey, request.contentType),
        publicUrl: this.publicUrlFor(objectKey),
        objectKey,
      });
    }

    return { uploads, maxObjectBytes: this.maxBytes };
  }

  /**
   * 04 §5: el alta de metadatos valida que la URL pertenece al bucket y al
   * prefijo `{scope}/{gymId}/`; si no, VALIDATION_FAILED.
   */
  assertUrlInScope(url: string, scope: UploadScope, gymId: string): void {
    const prefix = `${this.publicBaseUrl.replace(/\/$/, '')}/${scope}/${gymId}/`;
    if (!url.startsWith(prefix)) {
      throw new DomainException(
        'VALIDATION_FAILED',
        `La URL «${url}» no corresponde al prefijo ${scope}/${gymId}/ de este almacenamiento.`,
      );
    }
  }

  private async signPut(objectKey: string, contentType: string): Promise<string> {
    if (!this.s3) {
      // Entorno sin credenciales (desarrollo/pruebas): se devuelve una URL
      // inerte para que el contrato sea ejercitable end-to-end.
      return `${this.publicUrlFor(objectKey)}?x-unsigned-dev=1`;
    }
    // Sin `ContentLength`: al firmarlo se convierte en un header exigido con un
    // valor exacto, y el cliente sube el tamaño real del fichero -> el
    // almacenamiento rechazaría cada PUT con SignatureDoesNotMatch. El tope de
    // `S3_MAX_OBJECT_BYTES` se aplica en el cliente antes de pedir la firma y,
    // en el bucket, con una política de tamaño máximo.
    return getSignedUrl(
      this.s3,
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        ContentType: contentType,
      }),
      { expiresIn: this.ttl },
    );
  }
}
