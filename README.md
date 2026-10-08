# PruebaElixir

Base para una prueba técnica con Elixir + Phoenix Channels + SurrealDB. Todavía
no hay dominio: solo infraestructura (socket con un channel `ping`, SDK de
SurrealDB y migraciones).

## Requisitos

- Elixir 1.20 / OTP 29
- Docker con `docker compose`

El `.env` del repo ya trae valores locales (no son credenciales reales). Lo leen
`docker compose` y `config/runtime.exs` (solo en dev y test; una variable
exportada en la shell tiene prioridad).

| Servicio  | URL                       |
|-----------|---------------------------|
| SurrealDB | http://127.0.0.1:8030     |
| Phoenix   | http://127.0.0.1:4020     |
| Socket    | ws://127.0.0.1:4020/socket/websocket |

## Arranque

```bash
docker compose up -d        # SurrealDB v3.2.1, espera a que quede "healthy"
mix deps.get
mix surreal.migrate         # crea namespace/base si faltan y aplica migraciones
mix tablero.seed            # datos de ejemplo del enunciado (necesita tu migración)
mix phx.server
```

Otras tareas: `mix surreal.status`, `mix surreal.rollback [--step N]`,
`mix surreal.create`.

`mix tablero.seed` carga `priv/surreal/seed.surql` sobre tu esquema: las tablas
`usuario`, `proyecto` y `ticket`, y las relaciones `miembro` y `asignado`, tienen
que existir con los nombres del enunciado. Se puede correr varias veces; va en
una transacción, así que si falla no deja datos a medias.

## Tests

```bash
mix test                    # sin base de datos (excluye @moduletag :surreal)
mix test --include surreal  # además los de integración; requiere docker compose up -d
```

Los tests de integración usan su propia base (`SURREALDB_DB_TEST`, por defecto
`test`) y le aplican las migraciones solos.

## Channel de ejemplo

`PruebaElixirWeb.UserSocket` está montado en `/socket`. El topic `"ping"`
responde `{"message": "pong"}` al evento `"ping"`.

## SDK de SurrealDB

Módulos en `lib/prueba_elixir/surreal/`: `Repo` (fachada), `Schema` (structs),
`Migrator`, `Client` (HTTP), `Config`, `Session`, `HttpcPool`, `UUIDv7` y
`Storage`.

Migraciones en `priv/surreal/migrations/`, con nombre
`<version>_<nombre>.surql` y su `<version>_<nombre>.down.surql`, por ejemplo
`000000002_create_items.surql`.

```elixir
defmodule PruebaElixir.Ejemplo do
  use PruebaElixir.Surreal.Schema

  surreal_schema "ejemplo" do
    field :nombre, :string
    field :cantidad, :integer
  end
end

alias PruebaElixir.Ejemplo
alias PruebaElixir.Surreal.Repo

{:ok, %Ejemplo{id: id}} = Repo.insert(Ejemplo, %{nombre: "uno", cantidad: 1})
{:ok, %Ejemplo{nombre: "uno"}} = Repo.get(Ejemplo, id)

# Los valores van siempre como $params. Por HTTP llegan como string, así que
# un número o una fecha se castean en la sentencia: type::int($min).
{:ok, [%Ejemplo{} | _]} =
  Repo.all(Ejemplo, "SELECT * FROM ejemplo WHERE cantidad >= type::int($min);", %{min: 1})

# Resultado crudo, uno por sentencia.
{:ok, [%{"status" => "OK", "result" => [%{"total" => _}]}]} =
  Repo.query("SELECT count() AS total FROM ejemplo GROUP ALL;")
```

También: `Repo.update/4`, `Repo.delete/3`, `Repo.transaction/3`,
`Repo.transaction_insert/2` y `Repo.transaction_update/2`. Un schema expone
`record_id/1` (`"ejemplo:abc"`) y `external_id/1` (`"abc"`).
