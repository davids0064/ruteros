-- =============================================================================
-- 003_placement_removal.test.sql — pgTAP
-- Valida la migración 007: liberación de inventario al desvincular presas y
-- respeto de los estados 'maintenance' / 'retired'.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(10);

-- --- Fixture -----------------------------------------------------------------
INSERT INTO users (id, email, username, password_hash, role) VALUES
    ('11111111-1111-1111-1111-111111111111','setter@test.io','setter1','x','route_setter');

INSERT INTO boulder_gyms (id, name, address, city, country) VALUES
    ('22222222-2222-2222-2222-222222222222','Gym Test','Calle 1','Bogotá','Colombia');

INSERT INTO grade_systems (id, name) VALUES
    ('33333333-3333-3333-3333-333333333333','V-Scale-Test');
INSERT INTO grade_values (id, system_id, level_label, rank_ordinal, weight_factor) VALUES
    ('44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333','V4',4,2.5);

INSERT INTO walls (id, gym_id, name, photo_url, width_cm, height_cm, default_incline_deg) VALUES
    ('55555555-5555-5555-5555-555555555555','22222222-2222-2222-2222-222222222222',
     'Muro A','s3://walls/a.jpg',300,400,25);

INSERT INTO hold_sets (id, gym_id, name, color_hex) VALUES
    ('66666666-6666-6666-6666-666666666666','22222222-2222-2222-2222-222222222222',
     'Set Regletas Amarillas','#FFD700');

-- h1: se retira del lienzo | h2: permanece | h3: entra en mantenimiento
INSERT INTO holds (id, set_id, image_crop_url) VALUES
    ('77777777-7777-7777-7777-777777777777','66666666-6666-6666-6666-666666666666','s3://h/1.png'),
    ('88888888-8888-8888-8888-888888888888','66666666-6666-6666-6666-666666666666','s3://h/2.png'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','66666666-6666-6666-6666-666666666666','s3://h/3.png');

INSERT INTO routes (id, wall_id, creator_id, title, target_grade_id, wall_incline_deg) VALUES
    ('99999999-9999-9999-9999-999999999999','55555555-5555-5555-5555-555555555555',
     '11111111-1111-1111-1111-111111111111','Bloque Test',
     '44444444-4444-4444-4444-444444444444', 25);

INSERT INTO placed_holds (route_id, hold_id, x_percent, y_percent, hold_role) VALUES
    ('99999999-9999-9999-9999-999999999999','77777777-7777-7777-7777-777777777777',10.5,90.0,'start'),
    ('99999999-9999-9999-9999-999999999999','88888888-8888-8888-8888-888888888888',55.2,15.0,'top'),
    ('99999999-9999-9999-9999-999999999999','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',40.0,50.0,'hand');

SELECT is(
    (SELECT count(*) FROM holds WHERE status='in_use'), 3::bigint,
    'Las tres presas colocadas quedan in_use'
);

-- --- H1: retirar una presa del lienzo la libera (PATCH /routes/:id) ----------
DELETE FROM placed_holds
WHERE route_id='99999999-9999-9999-9999-999999999999'
  AND hold_id='77777777-7777-7777-7777-777777777777';

SELECT is(
    (SELECT status FROM holds WHERE id='77777777-7777-7777-7777-777777777777'),
    'available'::hold_status_enum,
    'H1: retirar una presa de la ruta la devuelve a available'
);
SELECT is(
    (SELECT status FROM holds WHERE id='88888888-8888-8888-8888-888888888888'),
    'in_use'::hold_status_enum,
    'H1: la presa que permanece en la ruta sigue in_use'
);

-- --- H3: una presa en mantenimiento no se libera al retirarla ---------------
UPDATE holds SET status='maintenance'
WHERE id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DELETE FROM placed_holds
WHERE route_id='99999999-9999-9999-9999-999999999999'
  AND hold_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT is(
    (SELECT status FROM holds WHERE id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'maintenance'::hold_status_enum,
    'H3: retirar una presa en mantenimiento no la marca available'
);

-- --- H3: una presa no disponible no puede colocarse -------------------------
SELECT throws_ok(
    $$INSERT INTO placed_holds (route_id, hold_id, x_percent, y_percent)
      VALUES ('99999999-9999-9999-9999-999999999999',
              'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 30, 30)$$,
    '55006',
    NULL,
    'H3: colocar una presa en maintenance aborta con 55006 (-> 409 HOLD_NOT_AVAILABLE)'
);

SELECT throws_ok(
    $$INSERT INTO placed_holds (route_id, hold_id, x_percent, y_percent)
      VALUES ('99999999-9999-9999-9999-999999999999',
              '88888888-8888-8888-8888-888888888888', 30, 30)$$,
    '23505',
    NULL,
    'La unicidad (route_id, hold_id) sigue prevaleciendo sobre el guard de estado'
);

-- --- H3: el desmantelado tampoco pisa maintenance ---------------------------
UPDATE routes SET status='archived_dismantled'
WHERE id='99999999-9999-9999-9999-999999999999';

SELECT is(
    (SELECT status FROM holds WHERE id='88888888-8888-8888-8888-888888888888'),
    'available'::hold_status_enum,
    'Desmantelar libera las presas in_use de la ruta'
);
SELECT is(
    (SELECT status FROM holds WHERE id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'maintenance'::hold_status_enum,
    'H3: el desmantelado conserva el estado maintenance'
);

-- --- H2: borrar el muro en cascada no deja inventario huérfano --------------
INSERT INTO routes (id, wall_id, creator_id, title, target_grade_id, wall_incline_deg) VALUES
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','55555555-5555-5555-5555-555555555555',
     '11111111-1111-1111-1111-111111111111','Bloque 2',
     '44444444-4444-4444-4444-444444444444', 25);
INSERT INTO placed_holds (route_id, hold_id, x_percent, y_percent) VALUES
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','88888888-8888-8888-8888-888888888888',20,20);

SELECT is(
    (SELECT status FROM holds WHERE id='88888888-8888-8888-8888-888888888888'),
    'in_use'::hold_status_enum,
    'H2: la presa reutilizada en la ruta nueva vuelve a in_use'
);

DELETE FROM routes WHERE id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SELECT is(
    (SELECT status FROM holds WHERE id='88888888-8888-8888-8888-888888888888'),
    'available'::hold_status_enum,
    'H2: borrar la ruta libera su inventario vía cascada'
);

SELECT * FROM finish();
ROLLBACK;
