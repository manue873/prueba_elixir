defmodule PruebaElixir.Tablero do
  @moduledoc """
  Contexto público del tablero Nexora Labs.

  Es la única fachada que usa `TableroChannel`. Orquesta:
  - `Queries` — acceso a SurrealDB.
  - `Policy`  — reglas de autorización y de negocio.

  Todas las funciones devuelven `{:ok, term()}` o `{:error, razón}`,
  donde `razón` es un átomo que el canal convierte a string.
  """

  alias PruebaElixir.Tablero.{Policy, Queries}

  # ──────────────────────────────────────────────────────────────────────────
  # Usuarios y sesión
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Devuelve `{:ok, %Usuario{}}` si el usuario existe y está activo,
  `{:error, :usuario_invalido}` en caso contrario.
  Usado por `UserSocket.connect/3`.
  """
  def usuario_activo(usuario_id) when is_binary(usuario_id) do
    case Queries.get_usuario(usuario_id) do
      {:ok, %{activo: true} = usuario} -> {:ok, usuario}
      {:ok, _} -> {:error, :usuario_invalido}
      {:error, _} -> {:error, :usuario_invalido}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Membresía (usado en join del canal)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Devuelve `{:ok, %{rol: rol}}` si el usuario activo es miembro del proyecto,
  `{:error, :sin_acceso}` si no lo es.
  """
  def membresía(usuario_id, proyecto_id) do
    case Queries.membresía_activa(usuario_id, proyecto_id) do
      {:ok, nil} -> {:error, :sin_acceso}
      {:ok, %{rol: _} = memb} -> {:ok, memb}
      {:error, _} -> {:error, :sin_acceso}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Lectura
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Lista tickets del proyecto. Acepta `%{estado: estado}` como filtro opcional."
  def listar_tickets(proyecto_id, filtros \\ %{}) do
    Queries.listar_tickets(proyecto_id, filtros)
  end

  @doc "Resumen con conteo por estado de todos los tickets del proyecto."
  def resumen(proyecto_id) do
    Queries.resumen(proyecto_id)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Mutaciones
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Crea un ticket en el proyecto.
  El estado siempre inicia como `abierto` (lo establece la DB por DEFAULT).
  """
  def crear_ticket(proyecto_id, rol, attrs) do
    with :ok <- Policy.puede_mutar?(rol),
         :ok <- Policy.validar_crear(attrs) do
      Queries.crear_ticket(proyecto_id, normalizar_crear(attrs))
    end
  end

  @doc """
  Edita titulo, prioridad o puntos de un ticket.
  Solo los campos presentes se actualizan (MERGE parcial).
  """
  def editar_ticket(proyecto_id, ticket_id, rol, attrs) do
    with :ok <- Policy.puede_mutar?(rol),
         :ok <- Policy.validar_editar(attrs),
         {:ok, ticket} <- Queries.get_ticket(ticket_id),
         :ok <- Policy.mismo_proyecto?(ticket.proyecto, proyecto_id) do
      Queries.editar_ticket(ticket_id, normalizar_editar(attrs))
    end
  end

  @doc """
  Mueve un ticket a `nuevo_estado`.
  Valida que el ticket no esté cerrado y que tenga responsable si se mueve a
  `en_progreso`.
  """
  def mover_ticket(proyecto_id, ticket_id, rol, nuevo_estado) do
    with :ok <- Policy.puede_mutar?(rol),
         {:ok, ticket} <- Queries.get_ticket(ticket_id),
         :ok <- Policy.mismo_proyecto?(ticket.proyecto, proyecto_id),
         {:ok, asignado} <- Queries.asignado_actual(ticket_id),
         :ok <- Policy.transicion_valida?(ticket.estado, nuevo_estado, asignado) do
      Queries.mover_ticket(ticket_id, nuevo_estado)
    end
  end

  @doc """
  Asigna un usuario como responsable de un ticket.
  El usuario debe ser miembro activo del proyecto del ticket.
  Reemplaza al responsable anterior si lo hubiera.
  """
  def asignar_ticket(proyecto_id, ticket_id, usuario_asignado_id, rol) do
    with :ok <- Policy.puede_mutar?(rol),
         {:ok, ticket} <- Queries.get_ticket(ticket_id),
         :ok <- Policy.mismo_proyecto?(ticket.proyecto, proyecto_id),
         {:ok, true} <-
           Queries.miembro_activo_del_proyecto_del_ticket?(usuario_asignado_id, ticket_id) do
      Queries.asignar_ticket(usuario_asignado_id, ticket_id)
    else
      {:ok, false} -> {:error, :usuario_no_es_miembro}
      other -> other
    end
  end

  @doc """
  Quita el responsable actual de un ticket.
  """
  def desasignar_ticket(proyecto_id, ticket_id, rol) do
    with :ok <- Policy.puede_mutar?(rol),
         {:ok, ticket} <- Queries.get_ticket(ticket_id),
         :ok <- Policy.mismo_proyecto?(ticket.proyecto, proyecto_id) do
      Queries.desasignar_ticket(ticket_id)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Privado — normalización de parámetros de entrada
  # ──────────────────────────────────────────────────────────────────────────

  # Normaliza las claves a átomos y convierte puntos a entero si llegan como string.
  defp normalizar_crear(attrs) do
    attrs
    |> atomizar_claves()
    |> Map.take([:titulo, :prioridad, :puntos])
    |> normalizar_puntos()
  end

  defp normalizar_editar(attrs) do
    attrs
    |> atomizar_claves()
    |> Map.take([:titulo, :prioridad, :puntos])
    |> normalizar_puntos()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp atomizar_claves(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  rescue
    # to_existing_atom falla si el átomo no existe: ignoramos la clave
    _ -> Map.new(attrs, fn {k, v} -> {k, v} end)
  end

  defp normalizar_puntos(%{puntos: puntos} = attrs) when is_binary(puntos) do
    case Integer.parse(puntos) do
      {n, ""} -> Map.put(attrs, :puntos, n)
      _ -> attrs
    end
  end

  defp normalizar_puntos(attrs), do: attrs
end
