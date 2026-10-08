defmodule PruebaElixirWeb.TableroChannel do
  @moduledoc """
  Channel del tablero de trabajo en tiempo real.

  Topic: `tablero:<proyecto_id>` (ej. `tablero:web`).

  ## Conexión

  El usuario debe ser miembro activo del proyecto. Al hacer `join` exitoso
  se responde con `{:ok, %{tickets: [...]}, socket}`.

  ## Eventos de entrada (handle_in)

  | Evento        | Payload                                              |
  |---------------|------------------------------------------------------|
  | `listar`      | `%{}` o `%{"estado" => estado}`                      |
  | `resumen`     | `%{}`                                                |
  | `crear`       | `%{"titulo" => _, "prioridad" => _, "puntos" => _}`  |
  | `editar`      | `%{"ticket_id" => _, "titulo/prioridad/puntos" => _}`|
  | `mover`       | `%{"ticket_id" => _, "estado" => _}`                 |
  | `asignar`     | `%{"ticket_id" => _, "usuario_id" => _}`             |
  | `desasignar`  | `%{"ticket_id" => _}`                                |

  ## Broadcasts (solo en éxito)

  `ticket_creado`, `ticket_editado`, `ticket_movido`, `ticket_asignado`
  con payload `%{"ticket" => ticket_serializado}`.
  """

  use PruebaElixirWeb, :channel

  alias PruebaElixir.Tablero

  # ──────────────────────────────────────────────────────────────────────────
  # join
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def join("tablero:" <> proyecto_id, _payload, socket) do
    usuario_id = socket.assigns.usuario_id

    case Tablero.membresía(usuario_id, proyecto_id) do
      {:ok, %{rol: rol}} ->
        socket =
          socket
          |> assign(:proyecto_id, proyecto_id)
          |> assign(:rol, rol)

        # Cargamos los tickets tras asignar el socket para poder usar after_join.
        # send/2 con un mensaje propio es el patrón Phoenix para trabajo post-join.
        send(self(), :after_join)
        {:ok, socket}

      {:error, _} ->
        {:error, %{"reason" => "sin_acceso"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    proyecto_id = socket.assigns.proyecto_id

    case Tablero.listar_tickets(proyecto_id) do
      {:ok, tickets} ->
        push(socket, "tickets_iniciales", %{tickets: serializar_lista(tickets)})

      {:error, _} ->
        :ok
    end

    {:noreply, socket}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Lectura
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_in("listar", payload, socket) do
    proyecto_id = socket.assigns.proyecto_id
    filtros = build_filtros(payload)

    case Tablero.listar_tickets(proyecto_id, filtros) do
      {:ok, tickets} ->
        {:reply, {:ok, %{tickets: serializar_lista(tickets)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in("resumen", _payload, socket) do
    proyecto_id = socket.assigns.proyecto_id

    case Tablero.resumen(proyecto_id) do
      {:ok, resumen} ->
        {:reply, {:ok, %{resumen: resumen}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Mutaciones
  # ──────────────────────────────────────────────────────────────────────────

  def handle_in("crear", payload, socket) do
    %{proyecto_id: proyecto_id, rol: rol} = socket.assigns

    case Tablero.crear_ticket(proyecto_id, rol, payload) do
      {:ok, ticket} ->
        serializado = serializar(ticket)
        broadcast!(socket, "ticket_creado", %{ticket: serializado})
        {:reply, {:ok, %{ticket: serializado}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in("editar", %{"ticket_id" => ticket_id} = payload, socket) do
    %{proyecto_id: proyecto_id, rol: rol} = socket.assigns
    attrs = Map.drop(payload, ["ticket_id"])

    case Tablero.editar_ticket(proyecto_id, ticket_id, rol, attrs) do
      {:ok, ticket} ->
        serializado = serializar(ticket)
        broadcast!(socket, "ticket_editado", %{ticket: serializado})
        {:reply, {:ok, %{ticket: serializado}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in("mover", %{"ticket_id" => ticket_id, "estado" => nuevo_estado}, socket) do
    %{proyecto_id: proyecto_id, rol: rol} = socket.assigns

    case Tablero.mover_ticket(proyecto_id, ticket_id, rol, nuevo_estado) do
      {:ok, ticket} ->
        serializado = serializar(ticket)
        broadcast!(socket, "ticket_movido", %{ticket: serializado})
        {:reply, {:ok, %{ticket: serializado}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in(
        "asignar",
        %{"ticket_id" => ticket_id, "usuario_id" => usuario_asignado_id},
        socket
      ) do
    %{proyecto_id: proyecto_id, rol: rol} = socket.assigns

    case Tablero.asignar_ticket(proyecto_id, ticket_id, usuario_asignado_id, rol) do
      {:ok, ticket} ->
        serializado = serializar(ticket)
        broadcast!(socket, "ticket_asignado", %{ticket: serializado})
        {:reply, {:ok, %{ticket: serializado}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in("desasignar", %{"ticket_id" => ticket_id}, socket) do
    %{proyecto_id: proyecto_id, rol: rol} = socket.assigns

    case Tablero.desasignar_ticket(proyecto_id, ticket_id, rol) do
      {:ok, ticket} ->
        serializado = serializar(ticket)
        broadcast!(socket, "ticket_asignado", %{ticket: serializado})
        {:reply, {:ok, %{ticket: serializado}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  # Cláusula de guarda para payloads malformados
  def handle_in(evento, _payload, socket)
      when evento in ~w[editar mover asignar desasignar] do
    {:reply, {:error, %{"reason" => "payload_invalido"}}, socket}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Privado
  # ──────────────────────────────────────────────────────────────────────────

  # Serializa un ticket al contrato exacto de la API.
  defp serializar(ticket) do
    %{
      "id" => ticket.id,
      "titulo" => ticket.titulo,
      "estado" => ticket.estado,
      "prioridad" => ticket.prioridad,
      "puntos" => ticket.puntos,
      "asignado" => ticket.asignado,
      "creado" => ticket.creado && DateTime.to_iso8601(ticket.creado)
    }
  end

  defp serializar_lista(tickets), do: Enum.map(tickets, &serializar/1)

  # Convierte el átomo de error al string que entiende el cliente.
  defp error_reason(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp error_reason(reason), do: inspect(reason)

  # Construye el mapa de filtros desde el payload del evento `listar`.
  defp build_filtros(%{"estado" => estado}) when is_binary(estado) and estado != "",
    do: %{estado: estado}

  defp build_filtros(_), do: %{}
end
