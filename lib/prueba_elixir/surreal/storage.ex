defmodule PruebaElixir.Surreal.Storage do
  @moduledoc """
  Crea el namespace y la base configurados si no existen (equivalente a
  `mix ecto.create`). No viene del SDK original: es un paso previo propio de
  este repo.

  En SurrealDB v3.2.1 `DEFINE TABLE` falla con "The database '...' does not
  exist" sobre una base nueva, mientras que `DEFINE FIELD` la crea de forma
  implícita. Por eso el primer `Migrator.migrate/1` sobre un volumen vacío
  fallaba y dejaba `schema_migrations` como SCHEMALESS. Requiere un usuario
  root (o de namespace).
  """

  alias PruebaElixir.Surreal.{Config, Repo}

  @identifier ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec up(keyword()) :: {:ok, list()} | {:error, PruebaElixir.Surreal.Client.Error.t()}
  def up(opts \\ []) when is_list(opts) do
    config = Config.load(opts)
    namespace = identifier!(config.namespace, :namespace)
    database = identifier!(config.database, :database)

    # Define namespace y base de forma idempotente (IF NOT EXISTS). Un nombre
    # de namespace/base no puede ir como $param en DEFINE, por eso se valida
    # como identificador simple antes de escribirlo en la sentencia.
    Repo.query(
      """
      DEFINE NAMESPACE IF NOT EXISTS #{namespace};
      USE NS #{namespace};
      DEFINE DATABASE IF NOT EXISTS #{database};
      """,
      %{},
      opts
    )
  end

  defp identifier!(value, key) do
    if is_binary(value) and Regex.match?(@identifier, value) do
      value
    else
      raise ArgumentError,
            "SurrealDB #{key} must be a simple identifier to be created, got: #{inspect(value)}"
    end
  end
end
