import { Controller, Get, Inject } from '@nestjs/common';
import { sql } from 'kysely';
import { Public } from '../common/decorators/public.decorator';
import { KYSELY, type Db } from '../database/database.module';

/**
 * Health check de la plataforma (Railway `healthcheckPath`).
 *
 * Comprueba que el pool de PostgreSQL responde: un proceso vivo que no puede
 * hablar con la base de datos no debe recibir tráfico durante un despliegue.
 */
@Controller('health')
export class HealthController {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  @Public()
  @Get()
  async check(): Promise<{ status: 'ok'; database: 'up' }> {
    await sql`select 1`.execute(this.db);
    return { status: 'ok', database: 'up' };
  }
}
