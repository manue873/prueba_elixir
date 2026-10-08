defmodule Mix.Tasks.Surreal.Rollback do
  @moduledoc """
  Revierte la última migración SurrealDB aplicada usando su `.down.surql`.

      mix surreal.rollback
      mix surreal.rollback --step 2
  """

  use Mix.Task

  @shortdoc "Rollback latest SurrealDB migration"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    case PruebaElixir.Surreal.Migrator.rollback(opts(args) ++ [on_migration: &log_migration/2]) do
      {:ok, []} ->
        Mix.shell().info("No SurrealDB migrations to roll back")

      {:ok, versions} ->
        Mix.shell().info("Rolled back #{length(versions)} SurrealDB migrations")

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

  defp log_migration(:rollback_start, migration) do
    Mix.shell().info("== Rolling back #{migration.filename}")
  end

  defp log_migration(:rollback_stop, migration) do
    Mix.shell().info("== Rolled back #{migration.filename}")
  end

  defp log_migration(_event, _migration), do: :ok
end
