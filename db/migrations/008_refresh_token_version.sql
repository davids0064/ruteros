-- migrate:up
-- =============================================================================
-- 008_refresh_token_version.sql
-- Soporte de invalidación de refresh tokens.
--
-- 04_COMPONENT_SPECS.md §4.1 exige: "Un cambio de membresía invalida los
-- refresh tokens del usuario". Sin estado en servidor esa regla es
-- inexpresable, porque un JWT firmado no se puede retirar.
--
-- `token_version` se embebe como claim `tv` en el refresh token. Cualquier
-- mutación de gym_setters incrementa el contador del usuario afectado, y todo
-- refresh token emitido antes deja de validar en el acto.
-- =============================================================================

ALTER TABLE users
    ADD COLUMN token_version INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN users.token_version IS
    'Contador de invalidación de refresh tokens (claim `tv`). 04 §4.1.';

-- Sólo invalidan los cambios que RECORTAN privilegios: salir de 'authorized',
-- perder el rol de administrador, o borrar la membresía.
--
-- Las concesiones (INSERT, pending -> authorized, ascender a admin) quedan
-- fuera a propósito: un permiso nuevo jamás deja un token vigente
-- sobre-privilegiado, y cerrarle la sesión a alguien en el momento de
-- autorizarlo — o al fundador justo después de crear su boulder — sería un
-- efecto colateral absurdo. El permiso recién concedido aparece en el claim
-- en la siguiente renovación (<= 900 s); hasta entonces los guards lo
-- resuelven contra esta misma tabla.
CREATE OR REPLACE FUNCTION bump_user_token_version_on_membership_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND NOT (OLD.status = 'authorized' AND NEW.status <> 'authorized')
       AND NOT (OLD.is_gym_admin AND NOT NEW.is_gym_admin) THEN
        RETURN NULL;  -- la mutación sólo concede: nada que invalidar
    END IF;

    UPDATE users
    SET token_version = token_version + 1,
        updated_at    = CURRENT_TIMESTAMP
    WHERE id = COALESCE(NEW.user_id, OLD.user_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bump_token_version_on_membership
AFTER UPDATE OF status, is_gym_admin OR DELETE ON gym_setters
FOR EACH ROW
EXECUTE FUNCTION bump_user_token_version_on_membership_change();

-- migrate:down
DROP TRIGGER IF EXISTS trigger_bump_token_version_on_membership ON gym_setters;
DROP FUNCTION IF EXISTS bump_user_token_version_on_membership_change();
ALTER TABLE users DROP COLUMN IF EXISTS token_version;
