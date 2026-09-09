import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { DatabaseModule } from './database/database.module';
import { AuthModule } from './auth/auth.module';
import { GymsModule } from './gyms/gyms.module';
import { MembershipsModule } from './memberships/memberships.module';
import { GradesModule } from './grades/grades.module';
import { WallsModule } from './walls/walls.module';
import { InventoryModule } from './inventory/inventory.module';
import { RoutesModule } from './routes/routes.module';
import { UploadsModule } from './uploads/uploads.module';
import { HealthModule } from './health/health.module';
import { JwtAuthGuard } from './auth/guards/jwt-auth.guard';

/**
 * Los módulos mapean 1:1 con los Módulos 1-5 del PRD (04 §0.1).
 * El JwtAuthGuard es global: todo endpoint exige Bearer salvo los marcados
 * @Public() (RNF-4, 04 §2.1).
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, envFilePath: ['.env.local', '.env'] }),
    DatabaseModule,
    AuthModule,
    GymsModule,
    MembershipsModule,
    GradesModule,
    WallsModule,
    InventoryModule,
    RoutesModule,
    UploadsModule,
    HealthModule,
  ],
  providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }],
})
export class AppModule {}
