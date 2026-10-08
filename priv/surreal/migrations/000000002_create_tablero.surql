-- Migración 000000002: esquema SCHEMAFULL del tablero Nexora Labs.
-- Tablas: usuario, proyecto, ticket.
-- Relaciones: miembro (usuario->proyecto), asignado (usuario->ticket).
-- Todas las reglas de integridad viven aquí; la app confía en ellas.

-- ─── usuario ────────────────────────────────────────────────────────────────
DEFINE TABLE IF NOT EXISTS usuario SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS nombre  ON TABLE usuario TYPE string
  ASSERT string::len($value) > 0;
DEFINE FIELD IF NOT EXISTS email   ON TABLE usuario TYPE string
  ASSERT string::is_email($value);
DEFINE FIELD IF NOT EXISTS activo  ON TABLE usuario TYPE bool DEFAULT true;
DEFINE INDEX IF NOT EXISTS usuario_email ON TABLE usuario COLUMNS email UNIQUE;

-- ─── proyecto ────────────────────────────────────────────────────────────────
DEFINE TABLE IF NOT EXISTS proyecto SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS clave   ON TABLE proyecto TYPE string
  ASSERT string::len($value) > 0;
DEFINE FIELD IF NOT EXISTS nombre  ON TABLE proyecto TYPE string
  ASSERT string::len($value) > 0;
DEFINE INDEX IF NOT EXISTS proyecto_clave ON TABLE proyecto COLUMNS clave UNIQUE;

-- ─── ticket ──────────────────────────────────────────────────────────────────
DEFINE TABLE IF NOT EXISTS ticket SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS proyecto  ON TABLE ticket TYPE record<proyecto>;
DEFINE FIELD IF NOT EXISTS titulo    ON TABLE ticket TYPE string
  ASSERT string::len($value) > 0;
DEFINE FIELD IF NOT EXISTS estado    ON TABLE ticket TYPE string
  ASSERT $value IN ["abierto", "en_progreso", "resuelto", "cerrado"]
  DEFAULT "abierto";
DEFINE FIELD IF NOT EXISTS prioridad ON TABLE ticket TYPE string
  ASSERT $value IN ["baja", "media", "alta", "critica"]
  DEFAULT "media";
-- puntos: opcional (NONE si no se estima), pero si está, debe ser de Fibonacci.
DEFINE FIELD IF NOT EXISTS puntos    ON TABLE ticket TYPE option<int>
  ASSERT $value = NONE OR $value IN [1, 2, 3, 5, 8, 13];
DEFINE FIELD IF NOT EXISTS creado    ON TABLE ticket TYPE datetime
  DEFAULT time::now();

-- ─── miembro: usuario →[miembro]→ proyecto ───────────────────────────────────
-- TYPE RELATION garantiza que in siempre es un record de usuario y out de proyecto.
DEFINE TABLE IF NOT EXISTS miembro TYPE RELATION IN usuario OUT proyecto SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS rol ON TABLE miembro TYPE string
  ASSERT $value IN ["lider", "desarrollador", "lector"];
-- Un usuario no puede ser miembro del mismo proyecto dos veces.
DEFINE INDEX IF NOT EXISTS miembro_unico ON TABLE miembro COLUMNS in, out UNIQUE;

-- ─── asignado: usuario →[asignado]→ ticket ───────────────────────────────────
-- UNIQUE en `out` garantiza que cada ticket tiene como máximo un responsable.
DEFINE TABLE IF NOT EXISTS asignado TYPE RELATION IN usuario OUT ticket SCHEMAFULL;
DEFINE INDEX IF NOT EXISTS asignado_ticket_unico ON TABLE asignado COLUMNS out UNIQUE;
