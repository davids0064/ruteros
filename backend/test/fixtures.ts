import request from 'supertest';
import type { INestApplication } from '@nestjs/common';
import type { Db } from '../src/database/database.module';

export const API = '/api/v1';
export const BUCKET = 'https://test-bucket.s3.local';

export interface TestUser {
  id: string;
  email: string;
  username: string;
  accessToken: string;
  refreshToken: string;
}

let counter = 0;
const unique = () => `${Date.now().toString(36)}${(counter += 1).toString(36)}`;

export async function registerUser(app: INestApplication, prefix = 'setter'): Promise<TestUser> {
  const id = unique();
  const body = {
    email: `${prefix}_${id}@test.io`,
    password: 'contrasena-larga-1',
    username: `${prefix}_${id}`.toLowerCase().slice(0, 60),
  };
  const res = await request(app.getHttpServer()).post(`${API}/auth/register`).send(body).expect(201);
  return {
    id: res.body.user.id,
    email: body.email,
    username: body.username,
    accessToken: res.body.accessToken,
    refreshToken: res.body.refreshToken,
  };
}

/** Reemite el access token para que incluya las membresías recién creadas. */
export async function refresh(app: INestApplication, user: TestUser): Promise<TestUser> {
  const res = await request(app.getHttpServer())
    .post(`${API}/auth/refresh`)
    .send({ refreshToken: user.refreshToken })
    .expect(200);
  return { ...user, accessToken: res.body.accessToken, refreshToken: res.body.refreshToken };
}

export const auth = (user: TestUser) => ({ Authorization: `Bearer ${user.accessToken}` });

export async function createGym(app: INestApplication, owner: TestUser) {
  const res = await request(app.getHttpServer())
    .post(`${API}/gyms`)
    .set(auth(owner))
    .send({
      name: `Boulder ${unique()}`,
      address: 'Calle 1 # 2-3',
      city: 'Bogotá',
      country: 'Colombia',
    })
    .expect(201);
  return res.body as { id: string };
}

export async function createWall(
  app: INestApplication,
  user: TestUser,
  gymId: string,
  overrides: Record<string, unknown> = {},
) {
  const res = await request(app.getHttpServer())
    .post(`${API}/gyms/${gymId}/walls`)
    .set(auth(user))
    .send({
      name: 'Muro A',
      photoUrl: `${BUCKET}/wall_photo/${gymId}/2026/09/muro.png`,
      widthCm: 300,
      heightCm: 400,
      defaultInclineDeg: 25,
      ...overrides,
    })
    .expect(201);
  return res.body as { id: string };
}

export async function createSetWithHolds(
  app: INestApplication,
  user: TestUser,
  gymId: string,
  count: number,
  weight = 1.0,
) {
  const set = await request(app.getHttpServer())
    .post(`${API}/gyms/${gymId}/hold-sets`)
    .set(auth(user))
    .send({ name: `Set ${unique()}`, colorHex: '#FFD700' })
    .expect(201);

  const holds = await request(app.getHttpServer())
    .post(`${API}/hold-sets/${set.body.id}/holds/batch`)
    .set(auth(user))
    .send({
      holds: Array.from({ length: count }, (_, i) => ({
        imageCropUrl: `${BUCKET}/hold_crop/${gymId}/2026/09/h${unique()}_${i}.png`,
        typeCategory: 'crimp',
        difficultyRatingWeight: weight,
      })),
    })
    .expect(201);

  return { setId: set.body.id as string, holds: holds.body as Array<{ id: string }> };
}

export async function vScaleGrade(db: Db, label: string): Promise<string> {
  const row = await db
    .selectFrom('grade_values as gv')
    .innerJoin('grade_systems as gs', 'gs.id', 'gv.system_id')
    .select('gv.id')
    .where('gs.name', '=', 'V-Scale')
    .where('gs.gym_id', 'is', null)
    .where('gv.level_label', '=', label)
    .executeTakeFirstOrThrow();
  return row.id;
}

export const placements = (holdIds: string[]) =>
  holdIds.map((holdId, i) => ({
    holdId,
    xPercent: i % 2 === 0 ? 35 : 65,
    yPercent: 90 - i * 18,
    rotationDeg: 0,
    role: i === 0 ? 'start' : i === holdIds.length - 1 ? 'top' : 'hand',
  }));
