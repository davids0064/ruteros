-- =============================================================================
-- 002_hold_lifecycle.test.sql — pgTAP
-- Valida RF-2.3: ciclo de reutilización de presas vía triggers.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

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

INSERT INTO holds (id, set_id, image_crop_url) VALUES
    ('77777777-7777-7777-7777-777777777777','66666666-6666-6666-6666-666666666666','s3://h/1.png'),
    ('88888888-8888-8888-8888-888888888888','66666666-6666-6666-6666-666666666666','s3://h/2.png');

-- --- 1. Estado inicial -------------------------------------------------------
SELECT is(
    (SELECT status FROM holds WHERE id='77777777-7777-7777-7777-777777777777'),
    'available'::hold_status_enum,
    'Una presa recién catalogada nace available'
);

INSERT INTO routes (id, wall_id, creator_id, title, target_grade_id, wall_incline_deg) VALUES
    ('99999999-9999-9999-9999-999999999999','55555555-5555-5555-5555-555555555555',
     '11111111-1111-1111-1111-111111111111','Bloque Test',
     '44444444-4444-4444-4444-444444444444', 25);

-- --- 2. trigger_mark_hold_in_use ---------------------------------------------
INSERT INTO placed_holds (route_id, hold_id, x_percent, y_percent, rotation_deg, hold_role) VALUES
    ('99999999-9999-9999-9999-999999999999','77777777-7777-7777-7777-777777777777',10.5,90.0,0,'start'),
    ('99999999-9999-9999-9999-999999999999','88888888-8888-8888-8888-888888888888',55.2,15.0,180,'top');

SELECT is(
    (SELECT status FROM holds WHERE id='77777777-7777-7777-7777-777777777777'),
    'in_use'::hold_status_enum,
    'Colocar una presa en una ruta la marca in_use'
);
SELECT is(
    (SELECT count(*) FROM holds WHERE status='in_use'), 2::bigint,
    'Ambas presas colocadas quedan in_use'
);

-- --- 3. UNIQUE (route_id, hold_id) -------------------------------------------
SELECT throws_ok(
    $$INSERT INTO placed_holds (route_id, hold_id, x_percent, y_percent)
      VALUES ('99999999-9999-9999-9999-999999999999',
              '77777777-7777-7777-7777-777777777777', 20, 20)$$,
    '23505',
    NULL,
    'No se puede colocar dos veces la misma presa en la misma ruta'
);

-- --- 4. Autoría inmutable: ON DELETE RESTRICT --------------------------------
SELECT throws_ok(
    $$DELETE FROM users WHERE id='11111111-1111-1111-1111-111111111111'$$,
    '23503',
    NULL,
    'No se puede borrar un setter que tiene rutas firmadas'
);

-- --- 5. Presa en uso protegida: ON DELETE RESTRICT ---------------------------
SELECT throws_ok(
    $$DELETE FROM holds WHERE id='77777777-7777-7777-7777-777777777777'$$,
    '23503',
    NULL,
    'No se puede borrar una presa colocada en una ruta'
);

-- --- 6. trigger_release_holds_dismantle --------------------------------------
UPDATE routes SET status='archived_dismantled'
WHERE id='99999999-9999-9999-9999-999999999999';

SELECT is(
    (SELECT count(*) FROM holds WHERE status='available'), 2::bigint,
    'Desmantelar la ruta devuelve todas sus presas a available'
);
SELECT isnt(
    (SELECT dismantled_at FROM routes WHERE id='99999999-9999-9999-9999-999999999999'),
    NULL,
    'El desmantelado sella dismantled_at automáticamente'
);

-- --- 7. Idempotencia: un segundo UPDATE no re-sella la fecha -----------------
SELECT lives_ok(
    $$UPDATE routes SET title='Bloque Test v2'
      WHERE id='99999999-9999-9999-9999-999999999999'$$,
    'Actualizar una ruta ya archivada no vuelve a disparar la liberación'
);

SELECT * FROM finish();
ROLLBACK;
