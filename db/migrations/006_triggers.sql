-- migrate:up
-- =============================================================================
-- 006_triggers.sql
-- Ciclo de vida del inventario  [CANÓNICO — 03_DATA_MODELS.md]
-- Estas transiciones de estado viven en la BD; la capa de negocio NO debe
-- duplicarlas (RF-2.3).
-- =============================================================================

-- 1. Al asociar una presa a una ruta activa, la presa pasa a estar 'in_use'
CREATE OR REPLACE FUNCTION mark_hold_as_in_use()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE holds
    SET status = 'in_use'
    WHERE id = NEW.hold_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_mark_hold_in_use
AFTER INSERT ON placed_holds
FOR EACH ROW
EXECUTE FUNCTION mark_hold_as_in_use();

-- 2. Al desmantelar/archivar una ruta, sus presas vuelven a estar 'available'
CREATE OR REPLACE FUNCTION release_holds_on_route_dismantle()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'archived_dismantled' AND OLD.status != 'archived_dismantled' THEN
        UPDATE holds
        SET status = 'available'
        WHERE id IN (
            SELECT hold_id FROM placed_holds WHERE route_id = NEW.id
        );
        NEW.dismantled_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_release_holds_dismantle
BEFORE UPDATE ON routes
FOR EACH ROW
EXECUTE FUNCTION release_holds_on_route_dismantle();

-- migrate:down
DROP TRIGGER IF EXISTS trigger_release_holds_dismantle ON routes;
DROP TRIGGER IF EXISTS trigger_mark_hold_in_use ON placed_holds;
DROP FUNCTION IF EXISTS release_holds_on_route_dismantle();
DROP FUNCTION IF EXISTS mark_hold_as_in_use();
