defmodule Mix.Tasks.Tablero.Seed do
  @moduledoc """
  Carga los datos de ejemplo del enunciado (`priv/surreal/seed.surql`) en la
  base configurada.

      mix tablero.seed

  Los datos se insertan sobre tu esquema, así que antes tiene que estar
  aplicada tu migración (`mix surreal.migrate`). Se puede correr varias veces:
  borra lo que hubiera y vuelve a cargar todo en una transacción.
  """

  use Mix.Task

  alias PruebaElixir.Surreal.Repo

  @shortdoc "Carga los datos de ejemplo del tablero"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    path = Path.join(:code.priv_dir(:prueba_elixir), "surreal/seed.surql")

    case load(File.read!(path)) do
      :ok ->
        Mix.shell().info(
          "Datos de ejemplo cargados: 6 usuarios, 2 proyectos, 7 miembros, 8 tickets"
        )

      {:error, reason} ->
        Mix.raise("""
        No se pudieron cargar los datos de ejemplo: #{reason}

        ¿Está aplicada tu migración (mix surreal.migrate) y respeta los nombres
        de tablas y campos del enunciado?
        """)
    end
  end

  @doc false
  # Corre el seed y revisa el resultado de cada sentencia: SurrealDB responde
  # 200 aunque una sentencia falle, con status "ERR" en esa sentencia.
  def load(statement) do
    case Repo.query(statement) do
      {:ok, results} ->
        case Enum.find(results, &(&1["status"] != "OK")) do
          nil -> :ok
          failed -> {:error, inspect(failed["result"])}
        end

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end
end
