-- Migración de ejemplo: tabla `ejemplo` SCHEMAFULL (solo admite los campos definidos).
-- IF NOT EXISTS la hace idempotente. Sin $params: es esquema, no datos.
DEFINE TABLE IF NOT EXISTS ejemplo SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS nombre ON TABLE ejemplo TYPE string;
DEFINE FIELD IF NOT EXISTS cantidad ON TABLE ejemplo TYPE int;
