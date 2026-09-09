-- migrate:up
-- =============================================================================
-- 002_users_and_gyms.sql
-- Entidades raíz: users (PROPUESTA), boulder_gyms (CANÓNICA), gym_setters (PROPUESTA)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- users  [PROPUESTA — PENDIENTE DE APROBACIÓN]
-- Referenciada por: hold_sets.creator_id (ON DELETE SET NULL)
--                   routes.creator_id    (ON DELETE RESTRICT)
-- Derivada de: RF-4.1 (email/password o JWT provider),
--              RF-4.2 (username, foto de perfil, rol)
-- Nota: `boulder asociado` NO se modela como columna aquí porque el KPI
--       "el route setter puede estar vinculado a diferentes boulders" exige N:M
--       -> se resuelve en gym_setters.
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT,                       -- NULL si el alta es vía proveedor JWT externo
    auth_provider VARCHAR(50) NOT NULL DEFAULT 'password',
    provider_subject_id TEXT,                 -- `sub` del IdP externo
    username VARCHAR(60) NOT NULL UNIQUE,
    display_name VARCHAR(120),
    avatar_url TEXT,                          -- S3 URL de la foto de perfil
    role user_role_enum NOT NULL DEFAULT 'climber',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_users_auth_method CHECK (
        password_hash IS NOT NULL OR provider_subject_id IS NOT NULL
    ),
    CONSTRAINT uq_users_provider_subject UNIQUE (auth_provider, provider_subject_id)
);

CREATE INDEX idx_users_email ON users (email);

-- -----------------------------------------------------------------------------
-- boulder_gyms  [CANÓNICA — transcripción literal de 03_DATA_MODELS.md]
-- -----------------------------------------------------------------------------
CREATE TABLE boulder_gyms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    address TEXT NOT NULL,
    city VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(255),
    pricing_plans JSONB DEFAULT '{}'::jsonb, -- Estructura flexible para planes, tarifas y horarios
    logo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_boulder_gyms_city_country ON boulder_gyms (country, city);

-- -----------------------------------------------------------------------------
-- gym_setters  [PROPUESTA — PENDIENTE DE APROBACIÓN]
-- Tabla puente N:M presente en el ERD de 03_DATA_MODELS.md (boulder_gyms 1..N
-- gym_setters N..1 users).
-- Derivada de: US-01 "routers autorizados por el boulder" y del KPI
--              "Asociación route setter con boulder: puede estar vinculado a
--               diferentes boulders".
-- -----------------------------------------------------------------------------
CREATE TABLE gym_setters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES boulder_gyms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status membership_status_enum NOT NULL DEFAULT 'pending',
    is_gym_admin BOOLEAN NOT NULL DEFAULT FALSE, -- US-01: administrador del boulder
    authorized_by UUID REFERENCES users(id) ON DELETE SET NULL,
    authorized_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_gym_setter UNIQUE (gym_id, user_id)
);

CREATE INDEX idx_gym_setters_user ON gym_setters (user_id);
CREATE INDEX idx_gym_setters_gym ON gym_setters (gym_id);

-- migrate:down
DROP TABLE IF EXISTS gym_setters;
DROP TABLE IF EXISTS boulder_gyms;
DROP TABLE IF EXISTS users;
