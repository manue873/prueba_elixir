defmodule PruebaElixir.Tablero.Usuario do
  @moduledoc """
  Schema Elixir para la tabla `usuario` de SurrealDB.
  Campos: nombre, email, activo.
  """

  use PruebaElixir.Surreal.Schema

  surreal_schema "usuario" do
    field :nombre, :string
    field :email, :string
    field :activo, :boolean
  end
end
