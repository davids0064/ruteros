-- migrate:up
-- =============================================================================
-- 007_inventory_lifecycle_hardening.sql
-- Cierra tres huecos del ciclo de vida del inventario detectados al contrastar
-- 03_DATA_MODELS.md con 04_COMPONENT_SPECS.md §2.9:
--
--   H1  PATCH /routes/:id reemplaza placed_holds por completo, pero no existía
--       trigger AFTER DELETE: la presa retirada quedaba 'in_use' para siempre.
--   H2  routes.wall_id ON DELETE CASCADE (y el borrado directo de una ruta)
--       eliminaba placed_holds sin liberar el inventario. Mismo síntoma que H1.
--   H3  Ambos triggers canónicos pisaban 'maintenance' y 'retired' sin condición.
--
-- Sigue vigente la regla de oro de 04 §0.1: la transición available <-> in_use
-- vive AQUÍ, no en la capa de negocio.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- H3.a  mark_hold_as_in_use: sólo 'available' puede pasar a 'in_use'.
-- Una presa en 'maintenance' o 'retired' aborta la transacción con SQLSTATE
-- 55006 (object_in_use), que la capa de negocio traduce a
-- 409 HOLD_NOT_AVAILABLE (04 §2.2). Es defensa en profundidad: el servicio ya
-- hace SELECT ... FOR UPDATE en 04 §2.9.1 paso 3.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_hold_as_in_use()
RETURNS TRIGGER AS $$
DECLARE
    v_status hold_status_enum;
BEGIN
    SELECT status INTO v_status FROM holds WHERE id = NEW.hold_id FOR UPDATE;

    IF v_status IS DISTINCT FROM 'available' THEN
        RAISE EXCEPTION
            'La presa % no está disponible (estado actual: %)', NEW.hold_id, v_status
            USING ERRCODE = '55006';
    END IF;

    UPDATE holds
    SET status = 'in_use'
    WHERE id = NEW.hold_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- H3.b  release_holds_on_route_dismantle: sólo devuelve a 'available' las presas
-- que estaban efectivamente 'in_use'. Una presa marcada 'maintenance' o
-- 'retired' mientras la ruta vivía conserva su estado al desmantelar.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_holds_on_route_dismantle()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'archived_dismantled' AND OLD.status != 'archived_dismantled' THEN
        UPDATE holds
        SET status = 'available'
        WHERE status = 'in_use'
          AND id IN (
              SELECT hold_id FROM placed_holds WHERE route_id = NEW.id
          );
        NEW.dismantled_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- H1 + H2  Liberación al desvincular una presa de una ruta.
--
-- Se dispara al retirar una presa del lienzo (PATCH /routes/:id), al borrar la
-- ruta y al borrar el muro en cascada.
--
-- La presa sólo vuelve a 'available' si:
--   a) estaba 'in_use'  -> respeta 'maintenance' / 'retired' (H3), y
--   b) no queda colocada en ninguna OTRA ruta viva ('draft' o 'active')
--      -> las rutas 'archived_dismantled' conservan sus placed_holds como
--         registro histórico y no deben retener inventario.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_hold_on_placement_removal()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE holds h
    SET status = 'available'
    WHERE h.id = OLD.hold_id
      AND h.status = 'in_use'
      AND NOT EXISTS (
          SELECT 1
          FROM placed_holds ph
          JOIN routes r ON r.id = ph.route_id
          WHERE ph.hold_id = OLD.hold_id
            AND r.status <> 'archived_dismantled'
      );
    RETURN NULL;  -- AFTER DELETE: el valor de retorno se ignora
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_release_hold_on_placement_removal
AFTER DELETE ON placed_holds
FOR EACH ROW
EXECUTE FUNCTION release_hold_on_placement_removal();

-- -----------------------------------------------------------------------------
-- Contrato para la capa de negocio (PATCH /routes/:id, 04 §2.9):
-- el reemplazo total del set DEBE ejecutar DELETE de las placed_holds salientes
-- ANTES del INSERT de las entrantes. Al invertir el orden, una presa que
-- permanece en la ruta chocaría contra unique_hold_per_active_route.
-- -----------------------------------------------------------------------------

-- migrate:down
DROP TRIGGER IF EXISTS trigger_release_hold_on_placement_removal ON placed_holds;
DROP FUNCTION IF EXISTS release_hold_on_placement_removal();
-- Las funciones canónicas vuelven a su forma de 006_triggers.sql al revertir 006.
