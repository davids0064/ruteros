import { Global, Module, OnApplicationShutdown } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { Kysely, PostgresDialect } from 'kysely';
import { Pool, types as pgTypes } from 'pg';
import type { Database } from './schema';

export const KYSELY = 'KYSELY_CONNECTION';
export type Db = Kysely<Database>;

// PostgreSQL devuelve numeric/int8 como string por defecto. Los FLOAT
// (double precision, OID 701) ya llegan como number; forzamos int8 (OID 20)
// a number para que los COUNT(*) de HoldSetDTO/WallDTO viajen como number JSON
// tal como fija 04 §3.
pgTypes.setTypeParser(20, (v) => Number(v));
pgTypes.setTypeParser(1700, (v) => Number(v));

@Global()
@Module({
  imports: [ConfigModule],
  providers: [
    {
      provide: KYSELY,
      inject: [ConfigService],
      useFactory: (config: ConfigService): Db => {
        const pool = new Pool({
          connectionString: config.getOrThrow<string>('DATABASE_URL'),
          max: Number(config.get('DATABASE_POOL_MAX') ?? 10),
        });
        return new Kysely<Database>({ dialect: new PostgresDialect({ pool }) });
      },
    },
  ],
  exports: [KYSELY],
})
export class DatabaseModule implements OnApplicationShutdown {
  constructor() {}
  async onApplicationShutdown(): Promise<void> {
    // El pool se cierra vía destroy() del proveedor en tests; en producción
    // el proceso termina con la app.
  }
}
