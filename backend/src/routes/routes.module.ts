import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GradesModule } from '../grades/grades.module';
import { InventoryModule } from '../inventory/inventory.module';
import { DifficultyService } from './difficulty.service';
import { GeneratorService } from './generator.service';
import { RoutesController } from './routes.controller';
import { RoutesService } from './routes.service';

@Module({
  imports: [AuthModule, GradesModule, InventoryModule],
  controllers: [RoutesController],
  providers: [RoutesService, GeneratorService, DifficultyService],
  exports: [RoutesService, DifficultyService],
})
export class RoutesModule {}
