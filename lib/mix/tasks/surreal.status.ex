defmodule Mix.Tasks.Surreal.Status do
  @moduledoc """
  Muestra cada migración SurrealDB como `up` (aplicada) o `down` (pendiente).

      mix surreal.status
  """

  use Mix.Task

  @shortdoc "Show SurrealDB migration status"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    case PruebaElixir.Surreal.Migrator.status() do
      {:ok, migrations} ->
        Enum.each(migrations, fn migration ->
          status = if migration.applied?, do: "up", else: "down"
          Mix.shell().info("#{status}\t#{migration.version}\t#{migration.filename}")
        end)

      {:error, error} ->
        Mix.raise(Exception.message(error))
    end
  end
end
