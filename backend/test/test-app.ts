import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { Pool } from 'pg';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/all-exceptions.filter';
import { DomainException } from '../src/common/errors/domain.exception';
import { KYSELY, type Db } from '../src/database/database.module';

const DB_DIR = join(__dirname, '..', '..', 'db');

/**
 * Arnés de integración (04 §7): PostgreSQL 15 REAL vía Testcontainers.
 * Los triggers de 006/007 se ejercitan de verdad, nunca contra un mock.
 */
export interface TestHarness {
  app: INestApplication;
  db: Db;
  container: StartedPostgreSqlContainer;
  close: () => Promise<void>;
}

/** Ejecuta sólo la sección `-- migrate:up` de cada `.sql` plano. */
function upSection(sql: string): string {
  const [up] = sql.split('-- migrate:down');
  return up.replace('-- migrate:up', '');
}

export async function startHarness(): Promise<TestHarness> {
  const container = await new PostgreSqlContainer('postgres:15-alpine')
    .withDatabase('boulder_test')
    .start();

  const url = container.getConnectionUri();
  const pool = new Pool({ connectionString: url });

  const migrations = readdirSync(join(DB_DIR, 'migrations'))
    .filter((f) => f.endsWith('.sql'))
    .sort();
  for (const file of migrations) {
    await pool.query(upSection(readFileSync(join(DB_DIR, 'migrations', file), 'utf8')));
  }
  const seeds = readdirSync(join(DB_DIR, 'seeds')).filter((f) => f.endsWith('.sql')).sort();
  for (const file of seeds) {
    await pool.query(readFileSync(join(DB_DIR, 'seeds', file), 'utf8'));
  }
  await pool.end();

  process.env.DATABASE_URL = url;
  process.env.JWT_ISSUER = 'boulder-cosetter-test';
  delete process.env.JWT_PRIVATE_KEY_PATH;
  delete process.env.JWT_PUBLIC_KEY_PATH;
  process.env.S3_PUBLIC_BASE_URL = 'https://test-bucket.s3.local';

  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();

  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix('api/v1');
  app.useGlobalFilters(new AllExceptionsFilter());
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      exceptionFactory: (errors) =>
        new DomainException(
          'VALIDATION_FAILED',
          'La petición no supera la validación.',
          errors.map((e) => ({ field: e.property, constraints: e.constraints })),
        ),
    }),
  );
  await app.init();

  const db = app.get<Db>(KYSELY);

  return {
    app,
    db,
    container,
    close: async () => {
      await db.destroy();
      await app.close();
      await container.stop();
    },
  };
}
