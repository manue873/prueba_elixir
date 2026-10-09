defmodule PruebaElixir.Tablero.Queries do
  @moduledoc """
  Todo el SurrealQL del módulo `Tablero` vive aquí.

  Reglas:
  - Ninguna función interpola datos externos en la sentencia: solo $params escalares.
  - Las funciones devuelven `{:ok, term()} | {:error, Client.Error.t()}`.
  - El ordenamiento de tickets usa `array::find/2` para respetar la prioridad
    definida como enum: `critica`→0, `alta`→1, `media`→2, `baja`→3.
  """

  alias PruebaElixir.Surreal.{Client, Repo}
  alias PruebaElixir.Tablero.{Proyecto, Ticket, Usuario}

  # ──────────────────────────────────────────────────────────────────────────
  # Usuarios
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Busca un usuario por id y devuelve `{:ok, %Usuario{}}` o `{:ok, nil}`."
  def get_usuario(usuario_id) when is_binary(usuario_id) do
    Repo.get(Usuario, usuario_id)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Proyectos
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Busca un proyecto por id."
  def get_proyecto(proyecto_id) when is_binary(proyecto_id) do
    Repo.get(Proyecto, proyecto_id)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Membresías
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Devuelve `{:ok, %{rol: rol}}` si el usuario es miembro del proyecto,
  `{:ok, nil}` si no lo es.
  """
  def membresía(usuario_id, proyecto_id)
      when is_binary(usuario_id) and is_binary(proyecto_id) do
    # Navega el grafo: SELECT rol FROM miembro WHERE in = usuario AND out = proyecto.
    # in y out van como type::record para evitar interpolación.
    statement = """
    SELECT VALUE rol
    FROM miembro
    WHERE in = type::record("usuario", $usuario_id)
      AND out = type::record("proyecto", $proyecto_id)
    LIMIT 1;
    """

    case Repo.query(statement, %{usuario_id: usuario_id, proyecto_id: proyecto_id}) do
      {:ok, [%{"result" => [rol | _]} | _]} -> {:ok, %{rol: rol}}
      {:ok, _} -> {:ok, nil}
      {:error, _} = err -> err
    end
  end

  @doc """
  Devuelve `{:ok, %{rol: rol}}` si el usuario activo es miembro del proyecto,
  `{:ok, nil}` si no lo es o si el usuario no está activo.
  """
  def membresía_activa(usuario_id, proyecto_id)
      when is_binary(usuario_id) and is_binary(proyecto_id) do
    statement = """
    SELECT VALUE rol
    FROM miembro
    WHERE in = type::record("usuario", $usuario_id)
      AND out = type::record("proyecto", $proyecto_id)
      AND in.activo = true
    LIMIT 1;
    """

    case Repo.query(statement, %{usuario_id: usuario_id, proyecto_id: proyecto_id}) do
      {:ok, [%{"result" => [rol | _]} | _]} -> {:ok, %{rol: rol}}
      {:ok, _} -> {:ok, nil}
      {:error, _} = err -> err
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Tickets
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Lista los tickets de un proyecto, con el responsable resuelto por grafo.
  Orden: prioridad (critica→alta→media→baja) ASC, creado ASC.
  Acepta filtro opcional `%{estado: estado}`.
  """
  def listar_tickets(proyecto_id, filtros \\ %{}) when is_binary(proyecto_id) do
    {estado_clause, params} =
      case Map.get(filtros, :estado) do
        nil -> {"", %{proyecto_id: proyecto_id}}
        estado -> {"AND estado = $estado", %{proyecto_id: proyecto_id, estado: estado}}
      end

    # array::find_index devuelve el índice 0, 1, 2, 3 para ordenar por prioridad
    statement = """
    SELECT *,
      array::find_index(["critica", "alta", "media", "baja"], prioridad) AS orden_prioridad,
      (SELECT VALUE string::replace(string::split(string::concat(in, ""), ":")[1], "`", "")
       FROM asignado WHERE out = $parent.id LIMIT 1)[0] AS asignado
    FROM ticket
    WHERE proyecto = type::record("proyecto", $proyecto_id)
    #{estado_clause}
    ORDER BY
      orden_prioridad ASC,
      creado ASC;
    """

    Repo.all(Ticket, statement, params)
  end

  @doc "Busca un ticket por su id externo con el asignado resuelto por grafo."
  def get_ticket(ticket_id) when is_binary(ticket_id) do
    statement = """
    SELECT *,
      (SELECT VALUE string::replace(string::split(string::concat(in, ""), ":")[1], "`", "")
       FROM asignado WHERE out = $parent.id LIMIT 1)[0] AS asignado
    FROM type::record("ticket", $ticket_id);
    """

    case Repo.all(Ticket, statement, %{ticket_id: ticket_id}) do
      {:ok, [ticket]} -> {:ok, ticket}
      {:ok, []} -> {:error, %Client.Error{message: "ticket_no_encontrado"}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Crea un ticket con los atributos dados.
  `proyecto_id` se convierte en una referencia de tipo record.
  """
  def crear_ticket(proyecto_id, attrs) when is_binary(proyecto_id) and is_map(attrs) do
    # La DB impone el estado "abierto" por DEFAULT; se pasa explícitamente
    # para que el struct devuelto lo tenga correctamente.
    ticket_attrs =
      attrs
      |> Map.put(:proyecto, "proyecto:#{proyecto_id}")
      |> Map.put_new(:estado, "abierto")
      |> Map.put_new(:prioridad, "media")

    Repo.insert(Ticket, ticket_attrs)
  end

  @doc "Actualiza titulo, prioridad o puntos de un ticket (MERGE parcial)."
  def editar_ticket(ticket_id, attrs) when is_binary(ticket_id) and is_map(attrs) do
    # Solo los campos editables. Ignoramos cualquier otra clave.
    campos_editables = [:titulo, :prioridad, :puntos]

    cambios =
      attrs
      |> Map.take(campos_editables)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(cambios) == 0 do
      {:error, %Client.Error{message: "sin_cambios"}}
    else
      case Repo.update(Ticket, ticket_id, cambios) do
        {:ok, _} -> get_ticket(ticket_id)
        error -> error
      end
    end
  end

  @doc "Mueve un ticket a un nuevo estado."
  def mover_ticket(ticket_id, nuevo_estado)
      when is_binary(ticket_id) and is_binary(nuevo_estado) do
    case Repo.update(Ticket, ticket_id, %{estado: nuevo_estado}) do
      {:ok, _} -> get_ticket(ticket_id)
      error -> error
    end
  end

  @doc """
  Asigna un usuario a un ticket.
  Primero borra la relación existente (máximo 1 responsable) y luego crea la nueva.
  La unicidad del índice `asignado_ticket_unico` es la red de seguridad en DB.
  """
  def asignar_ticket(usuario_id, ticket_id)
      when is_binary(usuario_id) and is_binary(ticket_id) do
    statement = """
    DELETE asignado WHERE out = type::record("ticket", $ticket_id);
    RELATE (type::record("usuario", $usuario_id))->asignado->(type::record("ticket", $ticket_id));
    """

    case Repo.query(statement, %{usuario_id: usuario_id, ticket_id: ticket_id}) do
      {:ok, _} -> get_ticket(ticket_id)
      {:error, _} = err -> err
    end
  end

  @doc "Desasigna el responsable actual de un ticket."
  def desasignar_ticket(ticket_id) when is_binary(ticket_id) do
    statement = """
    DELETE asignado WHERE out = type::record("ticket", $ticket_id);
    """

    case Repo.query(statement, %{ticket_id: ticket_id}) do
      {:ok, _} -> get_ticket(ticket_id)
      {:error, _} = err -> err
    end
  end

  @doc """
  Devuelve el conteo de tickets del proyecto agrupados por estado.
  Siempre retorna los 4 estados, aunque alguno tenga 0.
  """
  def resumen(proyecto_id) when is_binary(proyecto_id) do
    statement = """
    SELECT estado, count() AS total
    FROM ticket
    WHERE proyecto = type::record("proyecto", $proyecto_id)
    GROUP BY estado;
    """

    case Repo.query(statement, %{proyecto_id: proyecto_id}) do
      {:ok, [%{"result" => rows} | _]} ->
        # Construye mapa con los 4 estados garantizados
        conteos =
          Map.new(rows, fn %{"estado" => estado, "total" => total} -> {estado, total} end)

        resumen =
          Map.merge(
            %{"abierto" => 0, "en_progreso" => 0, "resuelto" => 0, "cerrado" => 0},
            conteos
          )

        {:ok, resumen}

      {:ok, _} ->
        {:ok, %{"abierto" => 0, "en_progreso" => 0, "resuelto" => 0, "cerrado" => 0}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Resuelve el id externo del responsable actual de un ticket usando el grafo.
  Devuelve `{:ok, usuario_id}` o `{:ok, nil}`.
  """
  def asignado_actual(ticket_id) when is_binary(ticket_id) do
    statement = """
    SELECT VALUE string::replace(string::split(string::concat(in, ""), ":")[1], "`", "")
    FROM asignado
    WHERE out = type::record("ticket", $ticket_id)
    LIMIT 1;
    """

    case Repo.query(statement, %{ticket_id: ticket_id}) do
      {:ok, [%{"result" => [usuario_id | _]} | _]} -> {:ok, usuario_id}
      {:ok, _} -> {:ok, nil}
      {:error, _} = err -> err
    end
  end

  @doc """
  Verifica si un usuario es miembro activo del proyecto al que pertenece un ticket.
  Útil para validar asignaciones.
  """
  def miembro_activo_del_proyecto_del_ticket?(usuario_id, ticket_id)
      when is_binary(usuario_id) and is_binary(ticket_id) do
    statement = """
    SELECT VALUE count()
    FROM miembro
    WHERE in = type::record("usuario", $usuario_id)
      AND in.activo = true
      AND out = (SELECT VALUE proyecto FROM type::record("ticket", $ticket_id) LIMIT 1)[0]
    GROUP ALL;
    """

    case Repo.query(statement, %{usuario_id: usuario_id, ticket_id: ticket_id}) do
      {:ok, [%{"result" => [n]} | _]} when n > 0 -> {:ok, true}
      {:ok, _} -> {:ok, false}
      {:error, _} = err -> err
    end
  end
end
