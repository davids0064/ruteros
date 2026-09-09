-- =============================================================================
-- 001_schema_structure.test.sql — pgTAP
-- Valida que el esquema físico coincide EXACTAMENTE con 03_DATA_MODELS.md.
-- Ejecutar: pg_prove -d boulder_test db/tests/*.test.sql
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(35);

-- --- Tablas existen ----------------------------------------------------------
SELECT has_table('boulder_gyms');
SELECT has_table('users');
SELECT has_table('gym_setters');
SELECT has_table('grade_systems');
SELECT has_table('grade_values');
SELECT has_table('walls');
SELECT has_table('hold_sets');
SELECT has_table('holds');
SELECT has_table('routes');
SELECT has_table('placed_holds');

-- --- ENUMs canónicos: valores y orden ----------------------------------------
SELECT enum_has_labels('hold_status_enum', ARRAY['available','in_use','maintenance','retired']);
SELECT enum_has_labels('hold_type_enum',   ARRAY['crimp','sloper','jug','pinch','foothold','volume']);
SELECT enum_has_labels('route_status_enum',ARRAY['draft','active','archived_dismantled']);
SELECT enum_has_labels('hold_role_enum',   ARRAY['start','hand','foot_only','top']);

-- --- Columnas canónicas exactas (nombres inmutables) -------------------------
SELECT columns_are('placed_holds',
    ARRAY['id','route_id','hold_id','x_percent','y_percent','rotation_deg','hold_role']);
SELECT columns_are('holds',
    ARRAY['id','set_id','image_crop_url','type_category','status',
          'difficulty_rating_weight','bounding_box_data','created_at']);
SELECT columns_are('routes',
    ARRAY['id','wall_id','creator_id','title','target_grade_id','calculated_grade_id',
          'wall_incline_deg','status','created_at','dismantled_at']);
SELECT columns_are('hold_sets',
    ARRAY['id','gym_id','creator_id','name','color_hex','created_at']);
SELECT columns_are('boulder_gyms',
    ARRAY['id','name','address','city','country','phone','email',
          'pricing_plans','logo_url','created_at','updated_at']);

-- --- Tipos de columnas críticas ----------------------------------------------
SELECT col_type_is('placed_holds','x_percent','double precision');
SELECT col_type_is('placed_holds','rotation_deg','integer');
SELECT col_type_is('boulder_gyms','pricing_plans','jsonb');
SELECT col_type_is('holds','bounding_box_data','jsonb');
SELECT col_type_is('hold_sets','color_hex','character varying(7)');

-- --- Defaults canónicos ------------------------------------------------------
SELECT col_default_is('holds','status','available');
SELECT col_default_is('holds','type_category','crimp');
SELECT col_default_is('routes','status','active');
SELECT col_default_is('placed_holds','hold_role','hand');
SELECT col_default_is('placed_holds','rotation_deg',0);

-- --- Claves y restricciones --------------------------------------------------
SELECT col_is_unique('placed_holds', ARRAY['route_id','hold_id'],
    'unique_hold_per_active_route impide duplicar una presa en la misma ruta');
SELECT col_not_null('routes','creator_id', 'La autoría del setter es obligatoria');
SELECT col_is_null('routes','calculated_grade_id', 'El grado calculado es opcional');
SELECT col_not_null('routes','wall_incline_deg');

-- --- Reglas de borrado (autoría inmutable) -----------------------------------
SELECT is(
    (SELECT confdeltype FROM pg_constraint
     WHERE conrelid = 'routes'::regclass AND conname LIKE '%creator_id%'),
    'r'::"char",
    'routes.creator_id debe ser ON DELETE RESTRICT'
);
SELECT is(
    (SELECT confdeltype FROM pg_constraint
     WHERE conrelid = 'hold_sets'::regclass AND conname LIKE '%creator_id%'),
    'n'::"char",
    'hold_sets.creator_id debe ser ON DELETE SET NULL'
);

SELECT * FROM finish();
ROLLBACK;
