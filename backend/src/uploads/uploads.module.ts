import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { S3Client } from '@aws-sdk/client-s3';
import { AuthModule } from '../auth/auth.module';
import { UploadsController } from './uploads.controller';
import { S3_CLIENT, UploadsService } from './uploads.service';

@Module({
  imports: [ConfigModule, AuthModule],
  controllers: [UploadsController],
  providers: [
    UploadsService,
    {
      provide: S3_CLIENT,
      inject: [ConfigService],
      useFactory: (config: ConfigService): S3Client | undefined => {
        const accessKeyId = config.get<string>('AWS_ACCESS_KEY_ID');
        const secretAccessKey = config.get<string>('AWS_SECRET_ACCESS_KEY');
        if (!accessKeyId || !secretAccessKey) return undefined; // ver UploadsService.signPut

        const endpoint = config.get<string>('S3_ENDPOINT');
        return new S3Client({
          region: config.get<string>('S3_REGION') ?? 'us-east-1',
          credentials: { accessKeyId, secretAccessKey },
          ...(endpoint ? { endpoint, forcePathStyle: true } : {}),
        });
      },
    },
  ],
  exports: [UploadsService],
})
export class UploadsModule {}
