-- migrate:up
-- =============================================================================
-- 009_account_deletion.sql
-- Borrado de cuenta a petición del usuario (App Store, directriz 5.1.1(v)).
--
-- `routes.creator_id` era ON DELETE RESTRICT: un setter con rutas publicadas no
-- se podía borrar nunca. La autoría es inmutable (RF-4.3) en el sentido de que
-- nadie puede reasignarla, no en el de que el autor quede atado de por vida a
-- la plataforma.
--
-- Se pasa a SET NULL, como ya hacían walls.creator_id y hold_sets.creator_id.
-- La ruta sobrevive al borrado de su autor —el boulder no pierde su catálogo—
-- y la API la sirve como autoría anónima.
-- =============================================================================

ALTER TABLE routes DROP CONSTRAINT routes_creator_id_fkey;
ALTER TABLE routes ALTER COLUMN creator_id DROP NOT NULL;
ALTER TABLE routes
    ADD CONSTRAINT routes_creator_id_fkey
    FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE SET NULL;

-- migrate:down
DELETE FROM routes WHERE creator_id IS NULL;
ALTER TABLE routes DROP CONSTRAINT routes_creator_id_fkey;
ALTER TABLE routes ALTER COLUMN creator_id SET NOT NULL;
ALTER TABLE routes
    ADD CONSTRAINT routes_creator_id_fkey
    FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE RESTRICT;
