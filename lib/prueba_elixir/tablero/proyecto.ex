defmodule PruebaElixir.Tablero.Proyecto do
  @moduledoc """
  Schema Elixir para la tabla `proyecto` de SurrealDB.
  Campos: clave, nombre.
  """

  use PruebaElixir.Surreal.Schema

  surreal_schema "proyecto" do
    field :clave, :string
    field :nombre, :string
  end
end
