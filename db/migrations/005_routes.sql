-- migrate:up
-- =============================================================================
-- 005_routes.sql
-- routes / placed_holds  [CANÓNICAS — transcripción literal de 03_DATA_MODELS.md]
-- =============================================================================

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

CREATE INDEX idx_routes_wall_status ON routes (wall_id, status);
CREATE INDEX idx_routes_creator ON routes (creator_id);

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

CREATE INDEX idx_placed_holds_route ON placed_holds (route_id);

-- migrate:down
DROP TABLE IF EXISTS placed_holds;
DROP TABLE IF EXISTS routes;
