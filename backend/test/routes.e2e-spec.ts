import request from 'supertest';
import { startHarness, type TestHarness } from './test-app';
import {
  API,
  auth,
  createGym,
  createSetWithHolds,
  createWall,
  placements,
  refresh,
  registerUser,
  vScaleGrade,
  type TestUser,
} from './fixtures';

/**
 * Casos que no pueden faltar — 04_COMPONENT_SPECS.md §7.
 * Numerados igual que la lista de la especificación.
 */
describe('Rutas e inventario (04 §7)', () => {
  let h: TestHarness;
  let setter: TestUser;
  let gymId: string;
  let wallId: string;
  let v4: string;

  beforeAll(async () => {
    h = await startHarness();
  });

  afterAll(async () => {
    await h?.close();
  });

  beforeEach(async () => {
    setter = await registerUser(h.app, 'setter');
    const gym = await createGym(h.app, setter);
    gymId = gym.id;
    setter = await refresh(h.app, setter); // el token ya lleva la membresía
    const wall = await createWall(h.app, setter, gymId);
    wallId = wall.id;
    v4 = await vScaleGrade(h.db, 'V4');
  });

  const post = (path: string, user: TestUser, body: object) =>
    request(h.app.getHttpServer()).post(`${API}${path}`).set(auth(user)).send(body);

  const createRoute = (holdIds: string[], user = setter, title = 'Bloque Test') =>
    post('/routes', user, {
      wallId,
      creatorId: user.id,
      title,
      targetGradeId: v4,
      wallInclineDeg: 25,
      placedHolds: placements(holdIds),
    });

  it('2. POST /routes deja todas sus presas in_use (verifica el trigger)', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 3);
    const res = await createRoute(holds.map((x) => x.id)).expect(201);

    expect(res.body.creator.id).toBe(setter.id);
    expect(res.body.holdsCount).toBe(3);
    expect(res.body.placedHolds).toHaveLength(3);
    expect(res.body.placedHolds.every((p: { hold: { status: string } }) => p.hold.status === 'in_use')).toBe(true);

    const rows = await h.db
      .selectFrom('holds')
      .select('status')
      .where('id', 'in', holds.map((x) => x.id))
      .execute();
    expect(rows.every((r) => r.status === 'in_use')).toBe(true);
  });

  it('1. POST /routes con una presa in_use -> 409 HOLD_NOT_AVAILABLE', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 4);
    await createRoute(holds.slice(0, 2).map((x) => x.id)).expect(201);

    const res = await createRoute([holds[1].id, holds[2].id, holds[3].id]).expect(409);
    expect(res.body.errorCode).toBe('HOLD_NOT_AVAILABLE');
    expect(res.body.path).toBe(`${API}/routes`);
    expect(typeof res.body.timestamp).toBe('string');
  });

  it('3. POST /routes/:id/dismantle libera las presas y sella dismantled_at', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 3);
    const created = await createRoute(holds.map((x) => x.id)).expect(201);

    const res = await post(`/routes/${created.body.id}/dismantle`, setter, {}).expect(200);
    expect(res.body.status).toBe('archived_dismantled');
    expect(res.body.dismantledAt).toEqual(expect.any(String));

    const rows = await h.db
      .selectFrom('holds')
      .select('status')
      .where('id', 'in', holds.map((x) => x.id))
      .execute();
    expect(rows.every((r) => r.status === 'available')).toBe(true);
  });

  it('3b. Un segundo dismantle -> 409 ROUTE_ALREADY_DISMANTLED', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    const created = await createRoute(holds.map((x) => x.id)).expect(201);

    await post(`/routes/${created.body.id}/dismantle`, setter, {}).expect(200);
    const res = await post(`/routes/${created.body.id}/dismantle`, setter, {}).expect(409);
    expect(res.body.errorCode).toBe('ROUTE_ALREADY_DISMANTLED');
  });

  it('4. POST /routes con la misma presa dos veces -> 409 DUPLICATE_HOLD_IN_ROUTE', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    const res = await createRoute([holds[0].id, holds[0].id]).expect(409);
    expect(res.body.errorCode).toBe('DUPLICATE_HOLD_IN_ROUTE');
  });

  it('5. PATCH /routes/:id sobre una ruta ajena -> 403 NOT_ROUTE_AUTHOR', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    const created = await createRoute(holds.map((x) => x.id)).expect(201);

    let intruso = await registerUser(h.app, 'intruso');
    await post(`/gyms/${gymId}/setters`, intruso, {}).expect(201); // autopostulación
    const membresia = await h.db
      .selectFrom('gym_setters')
      .select('id')
      .where('user_id', '=', intruso.id)
      .executeTakeFirstOrThrow();
    await request(h.app.getHttpServer())
      .patch(`${API}/gyms/${gymId}/setters/${membresia.id}`)
      .set(auth(setter))
      .send({ status: 'authorized' })
      .expect(200);
    // Autorizar es una concesión: NO invalida la sesión del setter (migración 008).
    intruso = await refresh(h.app, intruso);

    const res = await request(h.app.getHttpServer())
      .patch(`${API}/routes/${created.body.id}`)
      .set(auth(intruso))
      .send({ title: 'Me la apropio' })
      .expect(403);
    expect(res.body.errorCode).toBe('NOT_ROUTE_AUTHOR');
  });

  it('5b. POST /routes con un creatorId ajeno -> 403 NOT_ROUTE_AUTHOR', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    const otro = await registerUser(h.app, 'otro');

    const res = await post('/routes', setter, {
      wallId,
      creatorId: otro.id,
      title: 'Autoría falsificada',
      targetGradeId: v4,
      wallInclineDeg: 25,
      placedHolds: placements(holds.map((x) => x.id)),
    }).expect(403);
    expect(res.body.errorCode).toBe('NOT_ROUTE_AUTHOR');
  });

  it('6. PATCH /holds/:id con status in_use -> 400 VALIDATION_FAILED', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    const res = await request(h.app.getHttpServer())
      .patch(`${API}/holds/${holds[0].id}`)
      .set(auth(setter))
      .send({ status: 'in_use' })
      .expect(400);
    expect(res.body.errorCode).toBe('VALIDATION_FAILED');
  });

  it('6b. PATCH /holds/:id no saca una presa de in_use -> 400 VALIDATION_FAILED', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    await createRoute(holds.map((x) => x.id)).expect(201);

    const res = await request(h.app.getHttpServer())
      .patch(`${API}/holds/${holds[0].id}`)
      .set(auth(setter))
      .send({ status: 'available' })
      .expect(400);
    expect(res.body.errorCode).toBe('VALIDATION_FAILED');
  });

  it('7. Dos POST /routes concurrentes sobre la misma presa: gana exactamente uno', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);
    const ids = holds.map((x) => x.id);

    const [a, b] = await Promise.all([
      createRoute(ids, setter, 'Carrera A'),
      createRoute(ids, setter, 'Carrera B'),
    ]);

    const statuses = [a.status, b.status].sort();
    expect(statuses).toEqual([201, 409]);

    const perdedor = a.status === 409 ? a : b;
    expect(perdedor.body.errorCode).toBe('HOLD_NOT_AVAILABLE');

    const rutas = await h.db
      .selectFrom('routes')
      .select('id')
      .where('wall_id', '=', wallId)
      .execute();
    expect(rutas).toHaveLength(1);
  });

  it('8. POST /routes con un targetGradeId de otro sistema -> 422 GRADE_SYSTEM_MISMATCH', async () => {
    const font = await vScaleGrade(h.db, 'V4'); // sistema V-Scale
    const wallFont = await createWall(h.app, setter, gymId, {
      name: 'Muro Font',
      defaultGradeSystemId: await h.db
        .selectFrom('grade_systems')
        .select('id')
        .where('name', '=', 'Fontainebleau')
        .where('gym_id', 'is', null)
        .executeTakeFirstOrThrow()
        .then((r) => r.id),
    });
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 2);

    const res = await post('/routes', setter, {
      wallId: wallFont.id,
      creatorId: setter.id,
      title: 'Sistema cruzado',
      targetGradeId: font,
      wallInclineDeg: 20,
      placedHolds: placements(holds.map((x) => x.id)),
    }).expect(422);
    expect(res.body.errorCode).toBe('GRADE_SYSTEM_MISMATCH');
  });

  it('10. Cualquier endpoint sin Authorization -> 401 UNAUTHENTICATED', async () => {
    const res = await request(h.app.getHttpServer()).get(`${API}/auth/me`).expect(401);
    expect(res.body.errorCode).toBe('UNAUTHENTICATED');

    const res2 = await request(h.app.getHttpServer()).post(`${API}/routes`).send({}).expect(401);
    expect(res2.body.errorCode).toBe('UNAUTHENTICATED');
  });

  it('PATCH /routes/:id reemplaza el set y libera las presas salientes (migración 007)', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 4);
    const ids = holds.map((x) => x.id);
    const created = await createRoute(ids.slice(0, 3)).expect(201);

    const res = await request(h.app.getHttpServer())
      .patch(`${API}/routes/${created.body.id}`)
      .set(auth(setter))
      .send({ placedHolds: placements([ids[0], ids[3]]) })
      .expect(200);

    expect(res.body.holdsCount).toBe(2);

    const estados = Object.fromEntries(
      (
        await h.db.selectFrom('holds').select(['id', 'status']).where('id', 'in', ids).execute()
      ).map((r) => [r.id, r.status]),
    );
    expect(estados[ids[0]]).toBe('in_use');
    expect(estados[ids[1]]).toBe('available'); // retirada del lienzo
    expect(estados[ids[2]]).toBe('available'); // retirada del lienzo
    expect(estados[ids[3]]).toBe('in_use');
  });

  it('US-07: el catálogo del muro expone grado y autoría del setter', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 3);
    await createRoute(holds.map((x) => x.id), setter, 'Bloque Público').expect(201);

    const res = await request(h.app.getHttpServer())
      .get(`${API}/walls/${wallId}/routes?status=active`)
      .expect(200);

    expect(res.body).toHaveLength(1);
    expect(res.body[0]).toMatchObject({
      title: 'Bloque Público',
      status: 'active',
      creator: { id: setter.id, username: setter.username },
      targetGrade: { levelLabel: 'V4' },
    });
    expect(res.body[0].calculatedGrade).toBeDefined();
  });

  it('RF-4.3: calculated_grade_id se calcula sin sobrescribir target_grade_id', async () => {
    const { holds } = await createSetWithHolds(h.app, setter, gymId, 3, 4.8);
    const res = await createRoute(holds.map((x) => x.id)).expect(201);

    expect(res.body.targetGrade.levelLabel).toBe('V4');
    expect(res.body.calculatedGrade.weightFactor).toBeGreaterThan(
      res.body.targetGrade.weightFactor,
    );
  });
});
