defmodule PruebaElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :prueba_elixir,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {PruebaElixir.Application, []},
      # :inets (httpc), :crypto y :ssl los usa el cliente SurrealDB.
      extra_applications: [:logger, :runtime_tools, :crypto, :inets, :ssl]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  # Versiones exactas (las que resolvió mix.lock). El SDK SurrealDB no añade
  # dependencias: usa :httpc de OTP y Jason, que ya trae Phoenix.
  defp deps do
    [
      {:phoenix, "1.8.15"},
      {:telemetry_metrics, "1.2.0"},
      {:telemetry_poller, "1.3.0"},
      {:jason, "1.4.5"},
      {:dns_cluster, "0.2.0"},
      {:bandit, "1.12.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      # SurrealDB v3.2.1 no crea la base con DEFINE TABLE: cada tarea de
      # migraciones asegura antes namespace y base (PruebaElixir.Surreal.Storage).
      "surreal.migrate": ["surreal.create", "surreal.migrate"],
      "surreal.rollback": ["surreal.create", "surreal.rollback"],
      "surreal.status": ["surreal.create", "surreal.status"],
      "tablero.seed": ["surreal.create", "tablero.seed"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
