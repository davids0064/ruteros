import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GymsController } from './gyms.controller';
import { GymsService } from './gyms.service';

@Module({
  imports: [AuthModule],
  controllers: [GymsController],
  providers: [GymsService],
  exports: [GymsService],
})
export class GymsModule {}
