import request from 'supertest';
import { startHarness, type TestHarness } from './test-app';
import {
  API,
  BUCKET,
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

/** Pruebas de contrato de los módulos 2.3 - 2.10 de 04_COMPONENT_SPECS.md. */
describe('Contrato REST (04 §2)', () => {
  let h: TestHarness;
  let owner: TestUser;
  let gymId: string;

  beforeAll(async () => {
    h = await startHarness();
  });

  afterAll(async () => {
    await h?.close();
  });

  beforeEach(async () => {
    owner = await registerUser(h.app, 'owner');
    gymId = (await createGym(h.app, owner)).id;
    owner = await refresh(h.app, owner);
  });

  const http = () => request(h.app.getHttpServer());

  describe('§2.3 Auth', () => {
    it('register devuelve AuthSessionDTO con role climber por defecto', async () => {
      const res = await http()
        .post(`${API}/auth/register`)
        .send({
          email: `nuevo_${Date.now()}@test.io`,
          password: 'contrasena-larga-1',
          username: `nuevo_${Date.now()}`,
          displayName: 'Nuevo Setter',
        })
        .expect(201);

      expect(res.body).toMatchObject({
        accessToken: expect.any(String),
        refreshToken: expect.any(String),
        expiresIn: 900,
        user: { role: 'climber', displayName: 'Nuevo Setter', memberships: [] },
      });
      expect(res.body.user).not.toHaveProperty('passwordHash');
    });

    it('rechaza contraseñas de menos de 10 caracteres', async () => {
      const res = await http()
        .post(`${API}/auth/register`)
        .send({ email: 'corto@test.io', password: 'corta', username: 'corto' })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
      expect(res.body.details).toEqual(
        expect.arrayContaining([expect.objectContaining({ field: 'password' })]),
      );
    });

    it('rechaza un email duplicado con 409 EMAIL_ALREADY_REGISTERED', async () => {
      const res = await http()
        .post(`${API}/auth/register`)
        .send({ email: owner.email, password: 'contrasena-larga-1', username: 'duplicado_x' })
        .expect(409);
      expect(res.body.errorCode).toBe('EMAIL_ALREADY_REGISTERED');
    });

    it('rechaza campos no declarados (forbidNonWhitelisted)', async () => {
      const res = await http()
        .post(`${API}/auth/login`)
        .send({ email: owner.email, password: 'contrasena-larga-1', role: 'admin' })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
    });

    it('login con credenciales erróneas -> 401 UNAUTHENTICATED', async () => {
      const res = await http()
        .post(`${API}/auth/login`)
        .send({ email: owner.email, password: 'no-es-la-clave' })
        .expect(401);
      expect(res.body.errorCode).toBe('UNAUTHENTICATED');
    });

    it('refresh rota el token y /auth/me expone las membresías', async () => {
      const rotado = await refresh(h.app, owner);
      expect(rotado.refreshToken).not.toBe(owner.refreshToken);

      // La rotación es de un solo uso: el token entregado queda muerto.
      const reuso = await http()
        .post(`${API}/auth/refresh`)
        .send({ refreshToken: owner.refreshToken })
        .expect(401);
      expect(reuso.body.errorCode).toBe('UNAUTHENTICATED');

      const me = await http().get(`${API}/auth/me`).set(auth(rotado)).expect(200);
      expect(me.body.memberships).toEqual([
        expect.objectContaining({ gymId, status: 'authorized', isGymAdmin: true }),
      ]);
    });
  });

  describe('D-06: el permiso recién concedido vale sin renovar el token', () => {
    it('el fundador opera su boulder con el access token anterior a crearlo', async () => {
      // `owner` de este bloque NO pasa por refresh: su JWT sigue sin la
      // membresía. Los guards deben resolverla contra gym_setters.
      const recien = await registerUser(h.app, 'fundador');
      const gym = await createGym(h.app, recien);

      const conClaimsViejos = await http()
        .get(`${API}/auth/me`)
        .set(auth(recien))
        .expect(200);
      expect(conClaimsViejos.body.memberships).toHaveLength(1);

      // Firmar subidas del boulder.
      await http()
        .post(`${API}/uploads/presign?gymId=${gym.id}`)
        .set(auth(recien))
        .send({ scope: 'hold_crop', contentType: 'image/png', count: 2 })
        .expect(201);

      // Crear inventario y darlo de alta.
      const { holds } = await createSetWithHolds(h.app, recien, gym.id, 2);
      expect(holds).toHaveLength(2);

      // Consultar y editar ese inventario.
      await http()
        .get(`${API}/gyms/${gym.id}/holds/available`)
        .set(auth(recien))
        .expect(200);
      await http()
        .patch(`${API}/holds/${holds[0].id}`)
        .set(auth(recien))
        .send({ typeCategory: 'jug' })
        .expect(200);

      // Y montar un bloque en un muro suyo.
      const wall = await createWall(h.app, recien, gym.id);
      await http()
        .post(`${API}/routes`)
        .set(auth(recien))
        .send({
          wallId: wall.id,
          creatorId: recien.id,
          title: 'Sin renovar el token',
          targetGradeId: await vScaleGrade(h.db, 'V4'),
          wallInclineDeg: 20,
          placedHolds: placements(holds.map((x) => x.id)),
        })
        .expect(201);
    });

    it('una revocación cierra la sesión larga, aunque el access token viva su TTL', async () => {
      let setter = await registerUser(h.app, 'revocado');
      const alta = await http()
        .post(`${API}/gyms/${gymId}/setters`)
        .set(auth(setter))
        .send({})
        .expect(201);
      await http()
        .patch(`${API}/gyms/${gymId}/setters/${alta.body.id}`)
        .set(auth(owner))
        .send({ status: 'authorized' })
        .expect(200);

      setter = await refresh(h.app, setter);
      await http()
        .get(`${API}/gyms/${gymId}/holds/available`)
        .set(auth(setter))
        .expect(200);

      await http()
        .patch(`${API}/gyms/${gymId}/setters/${alta.body.id}`)
        .set(auth(owner))
        .send({ status: 'revoked' })
        .expect(200);

      // 04 §4.1 acepta el desfase: el claim ya emitido sigue concediendo acceso
      // hasta que expire (<= 900 s). Los guards no consultan la BD en ese caso
      // porque el camino feliz no debe pagar un SELECT (RNF-3).
      await http()
        .get(`${API}/gyms/${gymId}/holds/available`)
        .set(auth(setter))
        .expect(200);

      // Lo que sí es inmediato: no puede renovar. La ventana se cierra sola.
      const renovacion = await http()
        .post(`${API}/auth/refresh`)
        .send({ refreshToken: setter.refreshToken })
        .expect(401);
      expect(renovacion.body.errorCode).toBe('UNAUTHENTICATED');

      // Y un token limpio, sin el claim caduco, sí se topa con la BD.
      const reciente = await registerUser(h.app, 'sin_claim');
      const res = await http()
        .get(`${API}/gyms/${gymId}/holds/available`)
        .set(auth(reciente))
        .expect(403);
      expect(res.body.errorCode).toBe('NOT_GYM_MEMBER');
    });
  });

  describe('§2.4 Gyms', () => {
    it('el creador queda autorizado y admin del boulder', async () => {
      const me = await http().get(`${API}/auth/me`).set(auth(owner)).expect(200);
      expect(me.body.memberships[0]).toMatchObject({ gymId, isGymAdmin: true });
    });

    it('serializa pricingPlans en camelCase (04 §3)', async () => {
      const res = await http()
        .patch(`${API}/gyms/${gymId}`)
        .set(auth(owner))
        .send({ pricingPlans: { mensual: 120000, dia: 20000 } })
        .expect(200);
      expect(res.body.pricingPlans).toEqual({ mensual: 120000, dia: 20000 });
      expect(res.body).not.toHaveProperty('pricing_plans');
    });

    it('un no-admin no puede editar el boulder -> 403 NOT_GYM_ADMIN', async () => {
      const ajeno = await registerUser(h.app, 'ajeno');
      const res = await http()
        .patch(`${API}/gyms/${gymId}`)
        .set(auth(ajeno))
        .send({ name: 'Secuestrado' })
        .expect(403);
      expect(res.body.errorCode).toBe('NOT_GYM_ADMIN');
    });

    it('GET /gyms es público y filtra por ciudad', async () => {
      const res = await http().get(`${API}/gyms?city=Bogotá`).expect(200);
      expect(res.body.some((g: { id: string }) => g.id === gymId)).toBe(true);
    });
  });

  describe('§2.5 Membresías', () => {
    it('la autopostulación queda pending y la autorización sella authorizedBy', async () => {
      const aspirante = await registerUser(h.app, 'aspirante');

      const alta = await http()
        .post(`${API}/gyms/${gymId}/setters`)
        .set(auth(aspirante))
        .send({})
        .expect(201);
      expect(alta.body).toMatchObject({ status: 'pending', isGymAdmin: false });

      const autorizada = await http()
        .patch(`${API}/gyms/${gymId}/setters/${alta.body.id}`)
        .set(auth(owner))
        .send({ status: 'authorized' })
        .expect(200);
      expect(autorizada.body).toMatchObject({ status: 'authorized', authorizedBy: owner.id });
      expect(autorizada.body.authorizedAt).toEqual(expect.any(String));
    });

    it('un miembro corriente no puede autorizar a otro -> 403 NOT_GYM_ADMIN', async () => {
      const aspirante = await registerUser(h.app, 'asp2');
      const alta = await http()
        .post(`${API}/gyms/${gymId}/setters`)
        .set(auth(aspirante))
        .send({})
        .expect(201);

      const res = await http()
        .patch(`${API}/gyms/${gymId}/setters/${alta.body.id}`)
        .set(auth(aspirante))
        .send({ status: 'authorized' })
        .expect(403);
      expect(res.body.errorCode).toBe('NOT_GYM_ADMIN');
    });

    it('revocar una membresía invalida el refresh token del setter (04 §4.1)', async () => {
      let setter = await registerUser(h.app, 'revocable');
      const alta = await http()
        .post(`${API}/gyms/${gymId}/setters`)
        .set(auth(setter))
        .send({})
        .expect(201);
      await http()
        .patch(`${API}/gyms/${gymId}/setters/${alta.body.id}`)
        .set(auth(owner))
        .send({ status: 'authorized' })
        .expect(200);

      setter = await refresh(h.app, setter); // la concesión no cierra la sesión

      await http()
        .patch(`${API}/gyms/${gymId}/setters/${alta.body.id}`)
        .set(auth(owner))
        .send({ status: 'revoked' })
        .expect(200);

      const res = await http()
        .post(`${API}/auth/refresh`)
        .send({ refreshToken: setter.refreshToken })
        .expect(401);
      expect(res.body.errorCode).toBe('UNAUTHENTICATED');
    });
  });

  describe('§2.6 Sistemas de grado', () => {
    it('expone las escalas globales sembradas con la Matriz Referencial (PRD §7)', async () => {
      const res = await http().get(`${API}/grade-systems`).expect(200);
      const vScale = res.body.find((s: { name: string }) => s.name === 'V-Scale');
      expect(vScale.gymId).toBeUndefined(); // global
      expect(vScale.values).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ levelLabel: 'V0', rankOrdinal: 0, weightFactor: 1.0 }),
          expect.objectContaining({ levelLabel: 'V4', rankOrdinal: 4, weightFactor: 2.5 }),
          expect.objectContaining({ levelLabel: 'V8', rankOrdinal: 8, weightFactor: 4.8 }),
        ]),
      );
    });

    it('crea una escala personalizada del boulder y la devuelve ordenada', async () => {
      const res = await http()
        .post(`${API}/gyms/${gymId}/grade-systems`)
        .set(auth(owner))
        .send({
          name: 'Escala Casa',
          values: [
            { levelLabel: 'Difícil', rankOrdinal: 2, weightFactor: 3.0 },
            { levelLabel: 'Fácil', rankOrdinal: 0, weightFactor: 1.0 },
          ],
        })
        .expect(201);

      expect(res.body.gymId).toBe(gymId);
      expect(res.body.values.map((v: { levelLabel: string }) => v.levelLabel)).toEqual([
        'Fácil',
        'Difícil',
      ]);
    });

    it('rechaza una escala con un solo nivel', async () => {
      const res = await http()
        .post(`${API}/gyms/${gymId}/grade-systems`)
        .set(auth(owner))
        .send({ name: 'Incompleta', values: [{ levelLabel: 'X', rankOrdinal: 0, weightFactor: 1 }] })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
    });
  });

  describe('§2.7 Muros', () => {
    it('registra el muro con la inclinación del giroscopio y cuenta rutas activas', async () => {
      const wall = await createWall(h.app, owner, gymId, { defaultInclineDeg: 32.5 });
      const res = await http().get(`${API}/walls/${wall.id}`).expect(200);
      expect(res.body).toMatchObject({
        gymId,
        creatorId: owner.id,
        defaultInclineDeg: 32.5,
        widthCm: 300,
        heightCm: 400,
        isPublic: false,
        activeRoutesCount: 0,
      });
    });

    it('rechaza una inclinación fuera de [-90, 90]', async () => {
      const res = await http()
        .post(`${API}/gyms/${gymId}/walls`)
        .set(auth(owner))
        .send({
          name: 'Imposible',
          photoUrl: `${BUCKET}/wall_photo/${gymId}/2026/09/x.png`,
          widthCm: 300,
          heightCm: 400,
          defaultInclineDeg: 120,
        })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
    });

    it('sin sesión sólo se ven los muros públicos (US-03)', async () => {
      await createWall(h.app, owner, gymId, { name: 'Privado', isPublic: false });
      await createWall(h.app, owner, gymId, { name: 'Público', isPublic: true });

      const anonimo = await http().get(`${API}/gyms/${gymId}/walls`).expect(200);
      expect(anonimo.body.map((w: { name: string }) => w.name)).toEqual(['Público']);

      const miembro = await http()
        .get(`${API}/gyms/${gymId}/walls`)
        .set(auth(owner))
        .expect(200);
      expect(miembro.body.length).toBe(2);
    });
  });

  describe('§2.8 Inventario', () => {
    it('el alta masiva nace available y cuenta en el set (RF-2.1)', async () => {
      const { setId, holds } = await createSetWithHolds(h.app, owner, gymId, 10);
      expect(holds).toHaveLength(10);
      expect(holds.every((x: { id: string } & Record<string, unknown>) => x.status === 'available')).toBe(true);

      const sets = await http()
        .get(`${API}/gyms/${gymId}/hold-sets`)
        .set(auth(owner))
        .expect(200);
      expect(sets.body.find((s: { id: string }) => s.id === setId)).toMatchObject({
        holdsCount: 10,
        availableCount: 10,
        colorHex: '#FFD700',
      });
    });

    it('rechaza una imageCropUrl fuera del prefijo hold_crop/{gymId}/ (04 §5)', async () => {
      const set = await http()
        .post(`${API}/gyms/${gymId}/hold-sets`)
        .set(auth(owner))
        .send({ name: 'Set intruso', colorHex: '#00FF00' })
        .expect(201);

      const res = await http()
        .post(`${API}/hold-sets/${set.body.id}/holds/batch`)
        .set(auth(owner))
        .send({
          holds: [{ imageCropUrl: 'https://otro-bucket.example/h.png', typeCategory: 'jug' }],
        })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
    });

    it('rechaza un colorHex mal formado', async () => {
      const res = await http()
        .post(`${API}/gyms/${gymId}/hold-sets`)
        .set(auth(owner))
        .send({ name: 'Set', colorHex: 'amarillo' })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
    });

    it('PATCH /holds permite recategorizar y mandar a mantenimiento (RF-2.2)', async () => {
      const { holds } = await createSetWithHolds(h.app, owner, gymId, 1);
      const res = await http()
        .patch(`${API}/holds/${holds[0].id}`)
        .set(auth(owner))
        .send({ typeCategory: 'sloper', difficultyRatingWeight: 3.2, status: 'maintenance' })
        .expect(200);
      expect(res.body).toMatchObject({
        typeCategory: 'sloper',
        difficultyRatingWeight: 3.2,
        status: 'maintenance',
      });
    });

    it('9. GET /gyms/:id/holds/available con 500 presas responde en < 500 ms (RNF-3)', async () => {
      const set = await http()
        .post(`${API}/gyms/${gymId}/hold-sets`)
        .set(auth(owner))
        .send({ name: 'Set masivo', colorHex: '#123456' })
        .expect(201);

      // 500 presas en lotes de 100 (ArrayMaxSize del DTO = 200).
      for (let lote = 0; lote < 5; lote += 1) {
        await http()
          .post(`${API}/hold-sets/${set.body.id}/holds/batch`)
          .set(auth(owner))
          .send({
            holds: Array.from({ length: 100 }, (_, i) => ({
              imageCropUrl: `${BUCKET}/hold_crop/${gymId}/2026/09/masiva_${lote}_${i}.png`,
              typeCategory: 'crimp',
            })),
          })
          .expect(201);
      }

      const t0 = process.hrtime.bigint();
      const res = await http()
        .get(`${API}/gyms/${gymId}/holds/available`)
        .set(auth(owner))
        .expect(200);
      const ms = Number(process.hrtime.bigint() - t0) / 1e6;

      expect(res.body.length).toBeGreaterThanOrEqual(500);
      expect(ms).toBeLessThan(500);
    });

    it('un no-miembro no ve el inventario -> 403 NOT_GYM_MEMBER', async () => {
      const ajeno = await registerUser(h.app, 'curioso');
      const res = await http()
        .get(`${API}/gyms/${gymId}/holds/available`)
        .set(auth(ajeno))
        .expect(403);
      expect(res.body.errorCode).toBe('NOT_GYM_MEMBER');
    });
  });

  describe('§2.9 Generación de propuesta (RF-4.1)', () => {
    it('propone un bloque sin persistir nada', async () => {
      const wall = await createWall(h.app, owner, gymId);
      const { setId } = await createSetWithHolds(h.app, owner, gymId, 12, 2.5);
      const systemId = await h.db
        .selectFrom('grade_systems')
        .select('id')
        .where('name', '=', 'V-Scale')
        .where('gym_id', 'is', null)
        .executeTakeFirstOrThrow()
        .then((r) => r.id);

      const res = await http()
        .post(`${API}/routes/generate`)
        .set(auth(owner))
        .send({
          wallId: wall.id,
          gradeSystemId: systemId,
          targetGradeId: await vScaleGrade(h.db, 'V4'),
          wallInclineDeg: 30,
          enabledSetIds: [setId],
        })
        .expect(200);

      expect(res.body.placedHolds.length).toBeGreaterThanOrEqual(2);
      expect(res.body.placedHolds[0]).not.toHaveProperty('id'); // aún no persistidas
      expect(res.body.placedHolds.at(-1).role).toBe('top');
      expect(res.body.rationale).toEqual(expect.stringContaining('V4'));
      expect(res.body.estimatedGradeId).toEqual(expect.any(String));

      // No persiste: ni rutas ni cambios de inventario.
      const rutas = await h.db.selectFrom('routes').select('id').where('wall_id', '=', wall.id).execute();
      expect(rutas).toHaveLength(0);
      const enUso = await h.db
        .selectFrom('holds')
        .select('id')
        .where('set_id', '=', setId)
        .where('status', '=', 'in_use')
        .execute();
      expect(enUso).toHaveLength(0);
    });

    it('sin presas disponibles -> 409 HOLD_NOT_AVAILABLE', async () => {
      const wall = await createWall(h.app, owner, gymId);
      const set = await http()
        .post(`${API}/gyms/${gymId}/hold-sets`)
        .set(auth(owner))
        .send({ name: 'Set vacío', colorHex: '#ABCDEF' })
        .expect(201);

      const res = await http()
        .post(`${API}/routes/generate`)
        .set(auth(owner))
        .send({
          wallId: wall.id,
          gradeSystemId: await h.db
            .selectFrom('grade_systems')
            .select('id')
            .where('name', '=', 'V-Scale')
            .where('gym_id', 'is', null)
            .executeTakeFirstOrThrow()
            .then((r) => r.id),
          targetGradeId: await vScaleGrade(h.db, 'V4'),
          wallInclineDeg: 20,
          enabledSetIds: [set.body.id],
        })
        .expect(409);
      expect(res.body.errorCode).toBe('HOLD_NOT_AVAILABLE');
    });
  });

  describe('§2.10 Uploads', () => {
    it('devuelve N URLs prefirmadas bajo {scope}/{gymId}/{yyyy}/{MM}/', async () => {
      const res = await http()
        .post(`${API}/uploads/presign?gymId=${gymId}`)
        .set(auth(owner))
        .send({ scope: 'hold_crop', contentType: 'image/png', count: 10 })
        .expect(201);

      expect(res.body.uploads).toHaveLength(10);
      const now = new Date();
      const prefijo = `hold_crop/${gymId}/${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, '0')}/`;
      for (const u of res.body.uploads) {
        expect(u.objectKey.startsWith(prefijo)).toBe(true);
        expect(u.objectKey.endsWith('.png')).toBe(true);
        expect(u.publicUrl).toContain(u.objectKey);
      }
      // Claves únicas: ningún objeto pisa a otro.
      expect(new Set(res.body.uploads.map((u: { objectKey: string }) => u.objectKey)).size).toBe(10);
    });

    it('rechaza un lote de más de 50', async () => {
      const res = await http()
        .post(`${API}/uploads/presign?gymId=${gymId}`)
        .set(auth(owner))
        .send({ scope: 'hold_crop', contentType: 'image/png', count: 51 })
        .expect(400);
      expect(res.body.errorCode).toBe('VALIDATION_FAILED');
    });

    it('un no-miembro no puede firmar contra el prefijo del boulder', async () => {
      const ajeno = await registerUser(h.app, 'ajeno2');
      const res = await http()
        .post(`${API}/uploads/presign?gymId=${gymId}`)
        .set(auth(ajeno))
        .send({ scope: 'hold_crop', contentType: 'image/png' })
        .expect(403);
      expect(res.body.errorCode).toBe('NOT_GYM_MEMBER');
    });
  });
});
