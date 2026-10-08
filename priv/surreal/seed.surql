-- Datos de ejemplo del caso Nexora Labs (los mismos del enunciado).
--
-- Se cargan sobre TU esquema: las tablas usuario, proyecto y ticket, y las
-- relaciones miembro (usuario -> proyecto) y asignado (usuario -> ticket),
-- tienen que existir con los campos del "Modelo de datos mínimo".
--
-- Es re-ejecutable: primero borra lo que hubiera y todo va en una transacción,
-- así que si una sentencia falla no queda nada a medias.

BEGIN TRANSACTION;

-- Se borra primero lo que depende de otras tablas: relaciones, luego tickets.
DELETE asignado;
DELETE miembro;
DELETE ticket;
DELETE proyecto;
DELETE usuario;

-- Usuarios. Diego está inactivo; Gina no es miembro de ningún proyecto.
CREATE usuario:ana CONTENT { nombre: "Ana Torres", email: "ana@nexora.io", activo: true };
CREATE usuario:bruno CONTENT { nombre: "Bruno Díaz", email: "bruno@nexora.io", activo: true };
CREATE usuario:carla CONTENT { nombre: "Carla Méndez", email: "carla@nexora.io", activo: true };
CREATE usuario:diego CONTENT { nombre: "Diego Ramos", email: "diego@nexora.io", activo: false };
CREATE usuario:elena CONTENT { nombre: "Elena Vega", email: "elena@nexora.io", activo: true };
CREATE usuario:gina CONTENT { nombre: "Gina Paredes", email: "gina@nexora.io", activo: true };

-- Proyectos.
CREATE proyecto:web CONTENT { clave: "WEB", nombre: "Portal Web" };
CREATE proyecto:app CONTENT { clave: "APP", nombre: "App Móvil" };

-- Membresías: relación usuario -> miembro -> proyecto, con el rol.
RELATE usuario:ana->miembro->proyecto:web CONTENT { rol: "lider" };
RELATE usuario:bruno->miembro->proyecto:web CONTENT { rol: "desarrollador" };
RELATE usuario:carla->miembro->proyecto:web CONTENT { rol: "desarrollador" };
RELATE usuario:diego->miembro->proyecto:web CONTENT { rol: "desarrollador" };
RELATE usuario:elena->miembro->proyecto:web CONTENT { rol: "lector" };
RELATE usuario:bruno->miembro->proyecto:app CONTENT { rol: "lider" };
RELATE usuario:carla->miembro->proyecto:app CONTENT { rol: "desarrollador" };

-- Tickets. El ticket t5 no está estimado: no lleva campo puntos.
CREATE ticket:t1 CONTENT { proyecto: proyecto:web, titulo: "Login con Google", estado: "en_progreso", prioridad: "alta", puntos: 5, creado: <datetime>"2026-08-28T12:00:00Z" };
CREATE ticket:t2 CONTENT { proyecto: proyecto:web, titulo: "El botón de pago no responde", estado: "abierto", prioridad: "critica", puntos: 3, creado: <datetime>"2026-09-20T12:00:00Z" };
CREATE ticket:t3 CONTENT { proyecto: proyecto:web, titulo: "Actualizar el footer", estado: "cerrado", prioridad: "baja", puntos: 1, creado: <datetime>"2026-08-15T12:00:00Z" };
CREATE ticket:t4 CONTENT { proyecto: proyecto:web, titulo: "Error 500 en el perfil", estado: "abierto", prioridad: "alta", puntos: 2, creado: <datetime>"2026-09-18T12:00:00Z" };
CREATE ticket:t5 CONTENT { proyecto: proyecto:web, titulo: "Modo oscuro", estado: "abierto", prioridad: "media", creado: <datetime>"2026-09-25T12:00:00Z" };
CREATE ticket:t6 CONTENT { proyecto: proyecto:web, titulo: "Optimizar imágenes", estado: "resuelto", prioridad: "media", puntos: 3, creado: <datetime>"2026-09-05T12:00:00Z" };
CREATE ticket:t7 CONTENT { proyecto: proyecto:app, titulo: "Las push no llegan en iOS", estado: "en_progreso", prioridad: "critica", puntos: 5, creado: <datetime>"2026-09-22T12:00:00Z" };
CREATE ticket:t8 CONTENT { proyecto: proyecto:app, titulo: "Pantalla de onboarding", estado: "abierto", prioridad: "media", puntos: 8, creado: <datetime>"2026-09-14T12:00:00Z" };

-- Responsables: relación usuario -> asignado -> ticket.
RELATE usuario:bruno->asignado->ticket:t1;
RELATE usuario:carla->asignado->ticket:t2;
RELATE usuario:bruno->asignado->ticket:t3;
RELATE usuario:carla->asignado->ticket:t6;
RELATE usuario:bruno->asignado->ticket:t7;

COMMIT TRANSACTION;
