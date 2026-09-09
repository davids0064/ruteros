-- migrate:up
-- =============================================================================
-- 004_inventory.sql
-- hold_sets / holds  [CANÓNICAS — transcripción literal de 03_DATA_MODELS.md]
-- =============================================================================

CREATE TABLE hold_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES boulder_gyms(id) ON DELETE CASCADE,
    creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(100) NOT NULL,      -- Ej: "Set Regletas Amarillas Cheeta"
    color_hex VARCHAR(7) NOT NULL,   -- Ej: "#FFD700"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_hold_sets_gym ON hold_sets (gym_id);

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

-- Índice de soporte para RNF-3 (inventario de un muro en < 500 ms).
CREATE INDEX idx_holds_set_status ON holds (set_id, status);

-- migrate:down
DROP TABLE IF EXISTS holds;
DROP TABLE IF EXISTS hold_sets;
