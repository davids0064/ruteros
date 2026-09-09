# Esquema de Modelos de Datos

# Data Models & Database Specification (03_DATA_MODELS.md) — Boulder Co-Setter App

**Versión:** 1.0.0  
**Estado:** ESPECIFICACIÓN DE MODELOS MULTIUSUARIO, BOULDERS & INVENTARIO DINÁMICO  
**Motor de Persistencia:** PostgreSQL 15+ (vía Supabase / RDS / Native Postgres)  
**Enfoque:** SDD (Software-Driven Development)  

---

## 1. Diagrama Entidad-Relación (Visión General)

```text
               ┌───────────────────────┐
               │     boulder_gyms      │
               └───────────┬───────────┘
                           │ 1
        ┌──────────────────┼──────────────────┐
        │ N                │ N                │ N
┌───────┴────────┐ ┌───────┴────────┐ ┌───────┴────────┐
│  gym_setters   │ │   hold_sets    │ │     walls      │
└───────┬────────┘ └───────┬────────┘ └───────┬────────┘
        │ N                │ 1                │ 1
┌───────┴────────┐ ┌───────┴────────┐         │
│     users      │ │     holds      │         │
└───────┬────────┘ └───────┬────────┘         │
        │ 1                │ 1                │ N
        │          ┌───────┴────────┐ ┌───────┴────────┐
        └─────────>│     routes     │<│  grade_values  │
                   └───────┬────────┘ └───────┬────────┘
                           │ 1                │ 1
                   ┌───────┴────────┐         │
                   │  placed_holds  │<────────┘
                   └────────────────┘

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

CREATE TABLE hold_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES boulder_gyms(id) ON DELETE CASCADE,
    creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(100) NOT NULL,      -- Ej: "Set Regletas Amarillas Cheeta"
    color_hex VARCHAR(7) NOT NULL,   -- Ej: "#FFD700"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TYPE hold_status_enum AS ENUM ('available', 'in_use', 'maintenance', 'retired');
CREATE TYPE hold_type_enum AS ENUM ('crimp', 'sloper', 'jug', 'pinch', 'foothold', 'volume');

CREATE TABLE holds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    set_id UUID NOT NULL REFERENCES hold_sets(id) ON DELETE CASCADE,
    image_crop_url TEXT NOT NULL,  -- S3 URL del PNG recortado con canal alpha transparente
    type_category hold_type_enum NOT NULL DEFAULT 'crimp',
    status hold_status_enum NOT NULL DEFAULT 'available', -- Estado de reutilización
    difficulty_rating_weight FLOAT DEFAULT 1.0,           -- Multiplicador intrínseco del agarre
    bounding_box_data JSONB,                              -- { "width_px": 120, "height_px": 80 }
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TYPE route_status_enum AS ENUM ('draft', 'active', 'archived_dismantled');

CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wall_id UUID NOT NULL REFERENCES walls(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT, -- Setter autor inmutable
    title VARCHAR(100) NOT NULL,
    target_grade_id UUID NOT NULL REFERENCES grade_values(id),
    calculated_grade_id UUID REFERENCES grade_values(id),
    wall_incline_deg FLOAT NOT NULL, -- Ángulo capturado durante el armado
    status route_status_enum NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    dismantled_at TIMESTAMP WITH TIME ZONE
);

CREATE TYPE hold_role_enum AS ENUM ('start', 'hand', 'foot_only', 'top');

CREATE TABLE placed_holds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    hold_id UUID NOT NULL REFERENCES holds(id) ON DELETE RESTRICT,
    x_percent FLOAT NOT NULL,       -- Posición horizontal (0.00% a 100.00%)
    y_percent FLOAT NOT NULL,       -- Posición vertical (0.00% a 100.00%)
    rotation_deg INT NOT NULL DEFAULT 0, -- Grados de rotación (0° a 359°)
    hold_role hold_role_enum NOT NULL DEFAULT 'hand',
    CONSTRAINT unique_hold_per_active_route UNIQUE (route_id, hold_id)
);

-- 1. Al asociar una presa a una ruta activa, la presa pasa a estar 'in_use'
CREATE OR REPLACE FUNCTION mark_hold_as_in_use()
RETURNS TRIGGER AS $$ BEGIN     UPDATE holds      SET status = 'in_use'      WHERE id = NEW.hold_id;     RETURN NEW; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_mark_hold_in_use
AFTER INSERT ON placed_holds
FOR EACH ROW
EXECUTE FUNCTION mark_hold_as_in_use();

-- 2. Al desmantelar/archivar una ruta, sus presas vuelven a estar 'available'
CREATE OR REPLACE FUNCTION release_holds_on_route_dismantle()
RETURNS TRIGGER AS $$ BEGIN     IF NEW.status = 'archived_dismantled' AND OLD.status != 'archived_dismantled' THEN         UPDATE holds         SET status = 'available'         WHERE id IN (             SELECT hold_id FROM placed_holds WHERE route_id = NEW.id         );         NEW.dismantled_at = CURRENT_TIMESTAMP;     END IF;     RETURN NEW; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_release_holds_dismantle
BEFORE UPDATE ON routes
FOR EACH ROW
EXECUTE FUNCTION release_holds_on_route_dismantle();

export type HoldCategory = 'crimp' | 'sloper' | 'jug' | 'pinch' | 'foothold' | 'volume';
export type HoldStatus = 'available' | 'in_use' | 'maintenance' | 'retired';
export type HoldRole = 'start' | 'hand' | 'foot_only' | 'top';

export interface BoulderGymDTO {
  id: string;
  name: string;
  address: string;
  city: string;
  country: string;
  phone?: string;
  email?: string;
  pricingPlans: Record<string, any>;
}

export interface PlacedHoldDTO {
  id?: string;
  holdId: string;
  xPercent: number;
  yPercent: number;
  rotationDeg: number;
  role: HoldRole;
}

export interface RouteCreatePayload {
  wallId: string;
  creatorId: string; // Inmutable ID del Route Setter
  title: string;
  targetGradeId: string;
  wallInclineDeg: number;
  placedHolds: PlacedHoldDTO[];
}