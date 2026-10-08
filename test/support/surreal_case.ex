defmodule PruebaElixirWeb.SurrealCase do
  @moduledoc """
  Caso base para tests que requieren SurrealDB.

  Aplica las migraciones una vez por suite (setup_all) y limpia las tablas
  relevantes antes de cada test (setup) para garantizar aislamiento.

  Uso:
      use PruebaElixirWeb.SurrealCase
  """

  use ExUnit.CaseTemplate

  alias PruebaElixir.Surreal.{Migrator, Repo, Storage}

  using do
    quote do
      import PruebaElixirWeb.SurrealCase
    end
  end

  setup_all do
    {:ok, _} = Storage.up()
    {:ok, _versions} = Migrator.migrate()
    :ok
  end

  setup do
    # Limpia en orden: relaciones primero, tablas dependientes después.
    {:ok, _} = Repo.query("DELETE asignado;")
    {:ok, _} = Repo.query("DELETE miembro;")
    {:ok, _} = Repo.query("DELETE ticket;")
    {:ok, _} = Repo.query("DELETE proyecto;")
    {:ok, _} = Repo.query("DELETE usuario;")
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Helpers de inserción para tests
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Inserta un usuario. Acepta overrides con `attrs`."
  def insertar_usuario(attrs \\ %{}) do
    defaults = %{
      nombre: "Usuario Test",
      email: "test_#{:erlang.unique_integer([:positive])}@nexora.io",
      activo: true
    }

    PruebaElixir.Surreal.Repo.insert(
      PruebaElixir.Tablero.Usuario,
      Map.merge(defaults, attrs)
    )
  end

  @doc "Inserta un proyecto. Acepta overrides con `attrs`."
  def insertar_proyecto(attrs \\ %{}) do
    n = :erlang.unique_integer([:positive])

    defaults = %{
      clave: "PRJ#{n}",
      nombre: "Proyecto Test #{n}"
    }

    PruebaElixir.Surreal.Repo.insert(
      PruebaElixir.Tablero.Proyecto,
      Map.merge(defaults, attrs)
    )
  end

  @doc "Crea la relación miembro entre un usuario y un proyecto."
  def insertar_miembro(usuario_id, proyecto_id, rol \\ "desarrollador") do
    statement = """
    RELATE type::record("usuario", $usuario_id)->miembro->type::record("proyecto", $proyecto_id)
    CONTENT { rol: $rol };
    """

    PruebaElixir.Surreal.Repo.query(statement, %{
      usuario_id: usuario_id,
      proyecto_id: proyecto_id,
      rol: rol
    })
  end

  @doc "Inserta un ticket en un proyecto. Acepta overrides con `attrs`."
  def insertar_ticket(proyecto_id, attrs \\ %{}) do
    n = :erlang.unique_integer([:positive])

    defaults = %{
      titulo: "Ticket Test #{n}",
      prioridad: "media",
      estado: "abierto"
    }

    PruebaElixir.Tablero.Queries.crear_ticket(proyecto_id, Map.merge(defaults, attrs))
  end

  @doc "Asigna un usuario a un ticket."
  def asignar_ticket(usuario_id, ticket_id) do
    PruebaElixir.Tablero.Queries.asignar_ticket(usuario_id, ticket_id)
  end
end
