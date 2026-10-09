-- Revierte 000000001_create_ejemplo: quita los campos y luego la tabla (con sus datos).
REMOVE FIELD IF EXISTS cantidad ON TABLE ejemplo;
REMOVE FIELD IF EXISTS nombre ON TABLE ejemplo;
REMOVE TABLE IF EXISTS ejemplo;
