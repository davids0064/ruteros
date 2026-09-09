-- =============================================================================
-- 001_grade_systems.sql
-- Semilla de sistemas globales (gym_id IS NULL).
-- Los 4 valores marcados [PRD §7] son literales de la Matriz Referencial.
-- Los intermedios están INTERPOLADOS y requieren validación del dominio.
-- =============================================================================

INSERT INTO grade_systems (name, description, gym_id) VALUES
    ('V-Scale', 'Escala Hueco / V-Scale (Norteamérica)', NULL),
    ('Fontainebleau', 'Escala Fontainebleau (Europa)', NULL)
ON CONFLICT DO NOTHING;

-- V-Scale ---------------------------------------------------------------------
INSERT INTO grade_values (system_id, level_label, rank_ordinal, weight_factor)
SELECT gs.id, v.level_label, v.rank_ordinal, v.weight_factor
FROM grade_systems gs
CROSS JOIN (VALUES
    ('V0', 0, 1.0),   -- [PRD §7]
    ('V1', 1, 1.4),
    ('V2', 2, 1.8),
    ('V3', 3, 2.2),
    ('V4', 4, 2.5),   -- [PRD §7]
    ('V5', 5, 3.0),
    ('V6', 6, 3.6),
    ('V7', 7, 4.2),
    ('V8', 8, 4.8)    -- [PRD §7]
) AS v(level_label, rank_ordinal, weight_factor)
WHERE gs.name = 'V-Scale' AND gs.gym_id IS NULL
ON CONFLICT DO NOTHING;

-- Fontainebleau ---------------------------------------------------------------
-- rank_ordinal se alinea con V-Scale para permitir conversión entre sistemas.
INSERT INTO grade_values (system_id, level_label, rank_ordinal, weight_factor)
SELECT gs.id, v.level_label, v.rank_ordinal, v.weight_factor
FROM grade_systems gs
CROSS JOIN (VALUES
    ('4',   0, 1.0),
    ('4+',  1, 1.4),
    ('5',   2, 1.8),
    ('5+',  3, 2.2),
    ('6A',  4, 2.5),  -- [PRD §7]
    ('6A+', 5, 3.0),
    ('6B',  6, 3.6),
    ('6C',  7, 4.2),
    ('7A',  8, 4.8)   -- [PRD §7]
) AS v(level_label, rank_ordinal, weight_factor)
WHERE gs.name = 'Fontainebleau' AND gs.gym_id IS NULL
ON CONFLICT DO NOTHING;
