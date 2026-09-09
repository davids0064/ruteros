import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GradesController } from './grades.controller';
import { GradesService } from './grades.service';

@Module({
  imports: [AuthModule],
  controllers: [GradesController],
  providers: [GradesService],
  exports: [GradesService],
})
export class GradesModule {}
