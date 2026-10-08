defmodule Mix.Tasks.Surreal.Migrate do
  @moduledoc """
  Aplica las migraciones SurrealDB pendientes de `priv/surreal/migrations`.

      mix surreal.migrate
      mix surreal.migrate --step 1
  """

  use Mix.Task

  @shortdoc "Run SurrealDB migrations"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    case PruebaElixir.Surreal.Migrator.migrate(opts(args) ++ [on_migration: &log_migration/2]) do
      {:ok, []} ->
        Mix.shell().info("SurrealDB migrations already up")

      {:ok, versions} ->
        Mix.shell().info("Applied #{length(versions)} SurrealDB migrations")

      {:error, error} ->
        Mix.raise(Exception.message(error))
    end
  end

  defp opts(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [step: :integer], aliases: [n: :step])

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    validate_step!(opts)
  end

  defp validate_step!(opts) do
    case Keyword.get(opts, :step) do
      nil -> []
      step when step > 0 -> [step: step]
      _step -> Mix.raise("--step must be greater than 0")
    end
  end

  defp log_migration(:migration_start, migration) do
    Mix.shell().info("== Running #{migration.filename}")
  end

  defp log_migration(:migration_stop, migration) do
    Mix.shell().info("== Migrated #{migration.filename}")
  end

  defp log_migration(_event, _migration), do: :ok
end
