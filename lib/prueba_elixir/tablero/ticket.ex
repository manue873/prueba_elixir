defmodule PruebaElixir.Tablero.Ticket do
  @moduledoc """
  Schema Elixir para la tabla `ticket` de SurrealDB.

  El campo `asignado` es virtual: no se persiste en SurrealDB, se calcula en
  cada query mediante una subquery de grafo sobre la relación `asignado`.
  Contiene el id externo del usuario responsable (o `nil` si no hay ninguno).
  """

  use PruebaElixir.Surreal.Schema

  surreal_schema "ticket" do
    field :proyecto, :record, table: "proyecto"
    field :titulo, :string
    field :estado, :string
    field :prioridad, :string
    field :puntos, :integer
    field :creado, :datetime
    # Calculado en query, no se escribe en DB
    field :asignado, :string, virtual: true
  end
end
