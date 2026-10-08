defmodule PruebaElixir.Surreal.Migrator do
  @moduledoc """
  Ejecuta migraciones SurrealQL versionadas.

  Lee `priv/surreal/migrations/<version>_<nombre>.surql` (la versión es el
  prefijo numérico; cada una exige su `<version>_<nombre>.down.surql`) y
  registra las aplicadas en la tabla `schema_migrations`.

  Las migraciones no llevan `$params`: tabla de control y versión son
  identificadores/enteros validados antes de escribirse en la sentencia.
  """

  alias PruebaElixir.Surreal.{Client, Repo}

  @identifier ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec validate!(keyword()) :: :ok
  def validate!(opts \\ []) when is_list(opts) do
    opts
    |> migration_files()
    |> validate_migration_files!()

    :ok
  end

  def migrate(opts \\ []) do
    migration_table!(opts)
    step = Keyword.get(opts, :step, :all)
    validate_step!(step)
    migrations = opts |> migration_files() |> validate_migration_files!()

    with {:ok, _} <- ensure_schema_migrations(opts),
         {:ok, applied} <- applied(opts),
         :ok <- validate_applied!(applied, migrations) do
      migrations
      |> Enum.reduce_while({:ok, [], step}, fn migration, {:ok, ran, remaining} ->
        if step_done?(remaining) do
          {:halt, {:ok, ran, remaining}}
        else
          case apply_migration(migration, applied, opts) do
            {:ok, :skipped} -> {:cont, {:ok, ran, remaining}}
            {:ok, version} -> {:cont, {:ok, [version | ran], decrement_step(remaining)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end
      end)
      |> case do
        {:ok, ran, _remaining} -> {:ok, Enum.reverse(ran)}
        error -> error
      end
    end
  end

  def status(opts \\ []) do
    migration_table!(opts)
    migrations = opts |> migration_files() |> validate_migration_files!()

    with {:ok, _} <- ensure_schema_migrations(opts),
         {:ok, applied} <- applied(opts),
         :ok <- validate_applied!(applied, migrations) do
      status =
        migrations
        |> Enum.map(fn migration ->
          applied_migration = Map.get(applied, migration.version)

          %{
            version: migration.version,
            filename: migration.filename,
            applied?: not is_nil(applied_migration)
          }
        end)

      {:ok, status}
    end
  end

  def rollback(opts \\ []) do
    migration_table!(opts)
    step = Keyword.get(opts, :step, 1)
    validate_rollback_step!(step)
    migrations = opts |> migration_files() |> validate_migration_files!()

    with {:ok, _} <- ensure_schema_migrations(opts) do
      1..step
      |> Enum.reduce_while({:ok, []}, fn _index, {:ok, rolled_back} ->
        case rollback_once(opts, migrations) do
          {:ok, version} ->
            {:cont, {:ok, [version | rolled_back]}}

          {:error, %Client.Error{message: "No SurrealDB migrations have been applied"}}
          when rolled_back != [] ->
            {:halt, {:ok, rolled_back}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, versions} -> {:ok, Enum.reverse(versions)}
        error -> error
      end
    end
  end

  defp rollback_once(opts, migrations) do
    with {:ok, applied} <- applied(opts),
         :ok <- validate_applied!(applied, migrations),
         {:ok, latest} <- latest_applied(applied),
         {:ok, migration} <- migration_for(latest, migrations),
         {:ok, down_path} <- down_path(migration.path) do
      rollback_migration(migration, down_path, opts)
    end
  end

  defp rollback_migration(migration, down_path, opts) do
    # Ejecuta el .down.surql tal cual: es SurrealQL del repo, sin params.
    with :ok <- notify(opts, :rollback_start, migration),
         {:ok, _} <- Repo.query(File.read!(down_path), %{}, opts),
         {:ok, _} <- delete_migration(migration, opts) do
      :ok = notify(opts, :rollback_stop, migration)
      {:ok, migration.version}
    else
      {:error, error} ->
        {:error, migration_error("SurrealDB rollback failed", migration, error)}
    end
  end

  def ensure_schema_migrations(opts \\ []) do
    table = migration_table!(opts)

    # Crea (si no existe) la tabla de control con un índice UNIQUE por versión.
    # Un nombre de tabla no puede ir como $param en DEFINE; por eso
    # migration_table!/1 lo valida como identificador simple antes.
    Repo.query(
      """
      DEFINE TABLE IF NOT EXISTS #{table} SCHEMAFULL;
      DEFINE FIELD IF NOT EXISTS version ON TABLE #{table} TYPE int;
      DEFINE FIELD IF NOT EXISTS inserted_at ON TABLE #{table} TYPE datetime DEFAULT time::now();
      DEFINE INDEX IF NOT EXISTS #{table}_version ON TABLE #{table} COLUMNS version UNIQUE;
      """,
      %{},
      opts
    )
  end

  defp apply_migration(migration, applied, opts) do
    case Map.get(applied, migration.version) do
      nil ->
        # Ejecuta el .surql tal cual (SurrealQL del repo, sin params) y lo registra.
        with :ok <- notify(opts, :migration_start, migration),
             {:ok, _} <- Repo.query(migration.body, %{}, opts),
             {:ok, _} <- record_migration(migration, opts) do
          :ok = notify(opts, :migration_stop, migration)
          {:ok, migration.version}
        else
          {:error, error} ->
            {:error, migration_error("SurrealDB migration failed", migration, error)}
        end

      _applied_migration ->
        {:ok, :skipped}
    end
  end

  defp record_migration(migration, opts) do
    table = migration_table!(opts)

    # Registra la migración aplicada como schema_migrations:<version>. La
    # versión es un entero sacado del nombre del archivo, no un dato externo.
    Repo.query(
      """
      CREATE #{table}:#{migration.version} CONTENT {
        version: #{migration.version}
      };
      """,
      %{},
      opts
    )
  end

  defp applied(opts) do
    table = migration_table!(opts)

    # Lista las migraciones ya aplicadas, de la más antigua a la más nueva.
    case Repo.query("SELECT * FROM #{table} ORDER BY version ASC;", %{}, opts) do
      {:ok, [%{"result" => rows} | _]} when is_list(rows) ->
        normalize_applied(rows)

      {:ok, _} ->
        {:ok, %{}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_applied(rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn
      %{"version" => version} = row, {:ok, applied} ->
        try do
          {:cont, {:ok, Map.put(applied, normalize_version(version), row)}}
        rescue
          error ->
            {:halt,
             {:error,
              %Client.Error{
                message: "SurrealDB migration record has an invalid version",
                details: Exception.message(error)
              }}}
        end

      row, _acc ->
        {:halt,
         {:error,
          %Client.Error{
            message: "SurrealDB migration record is missing version",
            details: row
          }}}
    end)
  end

  defp latest_applied(applied) when map_size(applied) == 0 do
    {:error, %Client.Error{message: "No SurrealDB migrations have been applied"}}
  end

  defp latest_applied(applied) do
    {:ok, applied |> Map.keys() |> Enum.sort() |> List.last()}
  end

  defp migration_for(version, opts) do
    opts
    |> Enum.find(&(&1.version == version))
    |> case do
      nil ->
        {:error,
         %Client.Error{message: "Applied SurrealDB migration file is missing", details: version}}

      migration ->
        {:ok, migration}
    end
  end

  defp down_path(path) do
    down_path = String.replace_suffix(path, ".surql", ".down.surql")

    if File.exists?(down_path) do
      {:ok, down_path}
    else
      {:error,
       %Client.Error{
         message: "SurrealDB rollback requires a .down.surql file",
         details: down_path
       }}
    end
  end

  defp migration_files(opts) do
    opts
    |> Keyword.get_lazy(:path, fn ->
      Path.join(:code.priv_dir(:prueba_elixir), "surreal/migrations")
    end)
    |> Path.join("*.surql")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, ".down.surql"))
    |> Enum.map(&migration/1)
    |> Enum.sort_by(& &1.version)
  end

  defp validate_migration_files!(migrations) do
    versions = Enum.map(migrations, & &1.version)
    duplicate_versions = versions -- Enum.uniq(versions)

    orphaned_down =
      migrations
      |> List.first()
      |> case do
        nil ->
          []

        first ->
          first.path
          |> Path.dirname()
          |> Path.join("*.down.surql")
          |> Path.wildcard()
          |> Enum.reject(fn down_path ->
            up_path = String.replace_suffix(down_path, ".down.surql", ".surql")
            File.exists?(up_path)
          end)
      end

    missing_down =
      Enum.reject(migrations, fn migration ->
        File.exists?(String.replace_suffix(migration.path, ".surql", ".down.surql"))
      end)

    cond do
      duplicate_versions != [] ->
        raise ArgumentError,
              "SurrealDB migration versions must be unique: #{inspect(Enum.uniq(duplicate_versions))}"

      orphaned_down != [] ->
        raise ArgumentError,
              "SurrealDB down migration has no matching up migration: #{inspect(orphaned_down)}"

      missing_down != [] ->
        filenames = Enum.map(missing_down, & &1.filename)
        raise ArgumentError, "SurrealDB migrations require rollback files: #{inspect(filenames)}"

      true ->
        migrations
    end
  end

  defp validate_applied!(applied, migrations) do
    known_versions = migrations |> Enum.map(& &1.version) |> MapSet.new()
    unknown_versions = Map.keys(applied) |> Enum.reject(&MapSet.member?(known_versions, &1))

    if unknown_versions == [] do
      :ok
    else
      {:error,
       %Client.Error{
         message: "Applied SurrealDB migration file is missing",
         details: Enum.sort(unknown_versions)
       }}
    end
  end

  defp migration(path) do
    body = File.read!(path)
    filename = Path.basename(path)

    %{
      path: path,
      filename: filename,
      version: filename |> Path.rootname() |> version_from_name(),
      body: body
    }
  end

  defp notify(opts, event, migration) do
    case Keyword.get(opts, :on_migration) do
      fun when is_function(fun, 2) -> fun.(event, migration)
      _other -> nil
    end

    :ok
  end

  defp migration_error(message, migration, error) when is_map(migration) do
    %Client.Error{
      message: message,
      status: if(is_map(error), do: Map.get(error, :status)),
      details: %{
        version: migration.version,
        filename: migration.filename,
        reason: error_message(error)
      }
    }
  end

  defp migration_error(message, _migration, error),
    do: %Client.Error{message: message, details: error_message(error)}

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

  defp version_from_name(name) do
    case Regex.run(~r/^\d+/, name) do
      [version] ->
        String.to_integer(version)

      nil ->
        raise ArgumentError,
              "SurrealDB migration filename must start with a numeric version: #{name}"
    end
  end

  defp normalize_version(version) when is_integer(version), do: version

  defp normalize_version(version) when is_binary(version) do
    version
    |> version_from_name()
  end

  defp step_done?(:all), do: false
  defp step_done?(remaining), do: remaining <= 0

  defp decrement_step(:all), do: :all
  defp decrement_step(remaining), do: remaining - 1

  defp delete_migration(migration, opts) do
    table = migration_table!(opts)

    # Borra el registro de control de la versión revertida (tabla validada,
    # versión entera: no hay valores externos que parametrizar).
    Repo.query("DELETE FROM #{table}:#{migration.version};", %{}, opts)
  end

  defp migration_table!(opts) when is_list(opts) do
    table = Keyword.get(opts, :migration_table, "schema_migrations")

    if is_binary(table) and Regex.match?(@identifier, table) do
      table
    else
      raise ArgumentError,
            "SurrealDB migration table must be a simple identifier, got: #{inspect(table)}"
    end
  end

  defp migration_table!(_opts),
    do: raise(ArgumentError, "SurrealDB migration options must be a list")

  defp validate_step!(:all), do: :ok
  defp validate_step!(step) when is_integer(step) and step > 0, do: :ok

  defp validate_step!(_step),
    do: raise(ArgumentError, "SurrealDB migration step must be :all or a positive integer")

  defp validate_rollback_step!(step) when is_integer(step) and step > 0, do: :ok

  defp validate_rollback_step!(_step),
    do: raise(ArgumentError, "SurrealDB rollback step must be a positive integer")
end
