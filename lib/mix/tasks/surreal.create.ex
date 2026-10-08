defmodule Mix.Tasks.Surreal.Create do
  @moduledoc """
  Crea el namespace y la base SurrealDB configurados si no existen.

      mix surreal.create

  `mix.exs` lo encadena antes de `surreal.migrate`, `surreal.rollback` y
  `surreal.status`; ver `PruebaElixir.Surreal.Storage`.
  """

  use Mix.Task

  @shortdoc "Create the SurrealDB namespace and database"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    case PruebaElixir.Surreal.Storage.up() do
      {:ok, _result} -> :ok
      {:error, error} -> Mix.raise(Exception.message(error))
    end
  end
end
