-- migrate:up
-- =============================================================================
-- 001_extensions_and_enums.sql
-- Boulder Co-Setter App — Fundación del esquema
-- Fuente de verdad: .specs/03_DATA_MODELS.md
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()

-- -----------------------------------------------------------------------------
-- ENUMs CANÓNICOS (transcripción literal de 03_DATA_MODELS.md)
-- -----------------------------------------------------------------------------
CREATE TYPE hold_status_enum AS ENUM ('available', 'in_use', 'maintenance', 'retired');
CREATE TYPE hold_type_enum   AS ENUM ('crimp', 'sloper', 'jug', 'pinch', 'foothold', 'volume');
CREATE TYPE route_status_enum AS ENUM ('draft', 'active', 'archived_dismantled');
CREATE TYPE hold_role_enum   AS ENUM ('start', 'hand', 'foot_only', 'top');

-- -----------------------------------------------------------------------------
-- ENUMs PROPUESTOS  [PENDIENTE DE APROBACIÓN]
-- Derivados de: 01_PRD.md RF-4.1.2 "rol: escalador / route setter" y
--               US-01 "Como administrador".
-- -----------------------------------------------------------------------------
CREATE TYPE user_role_enum AS ENUM ('climber', 'route_setter', 'admin');

-- Derivado de: 01_PRD.md US-01 "Registro y autenticación de los routers
-- AUTORIZADOS por el boulder" -> la membresía necesita ciclo de vida.
CREATE TYPE membership_status_enum AS ENUM ('pending', 'authorized', 'revoked');

-- migrate:down
DROP TYPE IF EXISTS membership_status_enum;
DROP TYPE IF EXISTS user_role_enum;
DROP TYPE IF EXISTS hold_role_enum;
DROP TYPE IF EXISTS route_status_enum;
DROP TYPE IF EXISTS hold_type_enum;
DROP TYPE IF EXISTS hold_status_enum;
