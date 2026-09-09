import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { GradesService } from './grades.service';
import { GymAdminGuard } from '../auth/guards/gym-admin.guard';
import { Public } from '../common/decorators/public.decorator';
import { CreateGradeSystemPayload, type GradeSystemDTO, type GradeValueDTO } from './dto/grade.dto';

/** 04 §2.6 — Sistemas de Grado (RF-3.2) */
@Controller()
export class GradesController {
  constructor(private readonly grades: GradesService) {}

  @Public()
  @Get('grade-systems')
  findSystems(@Query('gymId') gymId?: string): Promise<GradeSystemDTO[]> {
    return this.grades.findSystems(gymId);
  }

  @Public()
  @Get('grade-systems/:systemId/values')
  findValues(@Param('systemId', ParseUUIDPipe) systemId: string): Promise<GradeValueDTO[]> {
    return this.grades.findValues(systemId);
  }

  @UseGuards(GymAdminGuard)
  @Post('gyms/:gymId/grade-systems')
  createSystem(
    @Param('gymId', ParseUUIDPipe) gymId: string,
    @Body() body: CreateGradeSystemPayload,
  ): Promise<GradeSystemDTO> {
    return this.grades.createSystem(gymId, body);
  }
}
