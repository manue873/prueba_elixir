-- Revierte 000000002_create_tablero: elimina en orden inverso a las dependencias.
-- Primero las relaciones (dependen de las tablas), luego las tablas.
REMOVE TABLE IF EXISTS asignado;
REMOVE TABLE IF EXISTS miembro;
REMOVE TABLE IF EXISTS ticket;
REMOVE TABLE IF EXISTS proyecto;
REMOVE TABLE IF EXISTS usuario;
