-- migrate:up
-- =============================================================================
-- 003_grades_and_walls.sql
-- grade_systems / grade_values / walls  [TODAS PROPUESTAS]
-- =============================================================================

-- -----------------------------------------------------------------------------
-- grade_systems  [PROPUESTA — PENDIENTE DE APROBACIÓN]
-- Derivada de: RF-3.2 "Soporte para múltiples sistemas de graduación" y de la
--              columna `System Name` de la Matriz Referencial (01_PRD.md §7).
-- `gym_id` NULL => sistema global (V-Scale, Font). NOT NULL => escala
-- personalizada propiedad de un boulder (RF-3.2 "escala personalizada").
-- -----------------------------------------------------------------------------
CREATE TABLE grade_systems (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES boulder_gyms(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,        -- Ej: "V-Scale", "Fontainebleau"
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Un nombre único entre los sistemas globales; y único por gym en los propios.
CREATE UNIQUE INDEX uq_grade_systems_global_name
    ON grade_systems (name) WHERE gym_id IS NULL;
CREATE UNIQUE INDEX uq_grade_systems_gym_name
    ON grade_systems (gym_id, name) WHERE gym_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- grade_values  [PROPUESTA — PENDIENTE DE APROBACIÓN]
-- Referenciada por: routes.target_grade_id (NOT NULL), routes.calculated_grade_id
-- Columnas derivadas 1:1 de la Matriz Referencial (01_PRD.md §7):
--   Level Label -> level_label | Rank Ordinal -> rank_ordinal
--   Weight Factor -> weight_factor  (alimenta el motor de dificultad, RF-3.2)
-- ON DELETE RESTRICT en el FK inverso: una escala en uso por una ruta no se borra.
-- -----------------------------------------------------------------------------
CREATE TABLE grade_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    system_id UUID NOT NULL REFERENCES grade_systems(id) ON DELETE CASCADE,
    level_label VARCHAR(20) NOT NULL,   -- Ej: "V4", "6A"
    rank_ordinal INT NOT NULL,          -- Orden absoluto comparable entre sistemas
    weight_factor FLOAT NOT NULL DEFAULT 1.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_grade_value_label   UNIQUE (system_id, level_label),
    CONSTRAINT uq_grade_value_ordinal UNIQUE (system_id, rank_ordinal),
    CONSTRAINT chk_grade_rank_positive   CHECK (rank_ordinal >= 0),
    CONSTRAINT chk_grade_weight_positive CHECK (weight_factor > 0)
);

CREATE INDEX idx_grade_values_system ON grade_values (system_id, rank_ordinal);

-- -----------------------------------------------------------------------------
-- walls  [PROPUESTA — PENDIENTE DE APROBACIÓN]
-- Referenciada por: routes.wall_id (ON DELETE CASCADE)
-- Derivada de: RF-3.1 "foto del muro, dimensiones físicas (W x H) e inclinación
--              por defecto (theta)" y US-03 "asociarlo a mi cuenta o dejarlo público".
-- `default_incline_deg` es el valor leído del giroscopio al registrar el muro;
-- `routes.wall_incline_deg` guarda el ángulo de la sesión concreta de armado.
-- -----------------------------------------------------------------------------
CREATE TABLE walls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES boulder_gyms(id) ON DELETE CASCADE,
    creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(100) NOT NULL,
    photo_url TEXT NOT NULL,            -- S3 URL de la foto base del muro (lienzo 2D)
    width_cm FLOAT NOT NULL,
    height_cm FLOAT NOT NULL,
    default_incline_deg FLOAT NOT NULL DEFAULT 0, -- theta capturado vía IMU/giroscopio
    default_grade_system_id UUID REFERENCES grade_systems(id) ON DELETE SET NULL,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,     -- US-03
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_wall_dimensions CHECK (width_cm > 0 AND height_cm > 0),
    CONSTRAINT chk_wall_incline    CHECK (default_incline_deg BETWEEN -90 AND 90)
);

CREATE INDEX idx_walls_gym ON walls (gym_id);

-- migrate:down
DROP TABLE IF EXISTS walls;
DROP TABLE IF EXISTS grade_values;
DROP TABLE IF EXISTS grade_systems;
