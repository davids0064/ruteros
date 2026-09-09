import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { WallsController } from './walls.controller';
import { WallsService } from './walls.service';

@Module({
  imports: [AuthModule],
  controllers: [WallsController],
  providers: [WallsService],
  exports: [WallsService],
})
export class WallsModule {}
