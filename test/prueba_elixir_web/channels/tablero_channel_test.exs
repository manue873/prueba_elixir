defmodule PruebaElixirWeb.TableroChannelTest do
  @moduledoc "Tests del channel TableroChannel contra SurrealDB real."

  use PruebaElixirWeb.ChannelCase
  use PruebaElixirWeb.SurrealCase, async: false

  @moduletag :surreal

  alias PruebaElixirWeb.UserSocket

  setup do
    {:ok, usuario} = insertar_usuario(%{activo: true})
    {:ok, lector} = insertar_usuario(%{email: "lector_ch@nexora.io", activo: true})
    {:ok, proyecto} = insertar_proyecto()
    {:ok, _} = insertar_miembro(usuario.id, proyecto.id, "desarrollador")
    {:ok, _} = insertar_miembro(lector.id, proyecto.id, "lector")

    socket = socket(UserSocket, "socket_#{usuario.id}", %{usuario_id: usuario.id})

    %{
      usuario: usuario,
      lector: lector,
      proyecto: proyecto,
      socket: socket
    }
  end

  # ──────────────────────────────────────────────────────────────────────────
  # join
  # ──────────────────────────────────────────────────────────────────────────

  describe "join tablero:<proyecto_id>" do
    test "miembro activo puede unirse y recibe tickets_iniciales", %{
      socket: socket,
      proyecto: p
    } do
      assert {:ok, _, joined} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert joined.assigns.proyecto_id == p.id
      assert joined.assigns.rol == "desarrollador"
      # Mensaje push tras join
      assert_push "tickets_iniciales", %{tickets: tickets}
      assert is_list(tickets)
    end

    test "usuario no miembro es rechazado", %{proyecto: p} do
      {:ok, externo} = insertar_usuario()
      socket = socket(UserSocket, "socket_ext", %{usuario_id: externo.id})
      assert {:error, %{"reason" => "sin_acceso"}} = join(socket, "tablero:#{p.id}", %{})
    end

    test "proyecto inexistente es rechazado", %{socket: socket} do
      assert {:error, %{"reason" => "sin_acceso"}} =
               join(socket, "tablero:no_existe", %{})
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # crear
  # ──────────────────────────────────────────────────────────────────────────

  describe "handle_in crear" do
    setup %{socket: socket, proyecto: p} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      %{socket: socket}
    end

    test "crea ticket y hace broadcast ticket_creado", %{socket: socket} do
      ref = push(socket, "crear", %{"titulo" => "Nuevo ticket", "prioridad" => "alta"})

      assert_reply ref, :ok, %{ticket: ticket}
      assert ticket["titulo"] == "Nuevo ticket"
      assert ticket["estado"] == "abierto"
      assert ticket["prioridad"] == "alta"

      assert_broadcast "ticket_creado", %{ticket: ^ticket}
    end

    test "lector recibe sin_permiso", %{proyecto: p, lector: l} do
      lector_socket = socket(UserSocket, "lector_sock", %{usuario_id: l.id})
      {:ok, _, lector_sock} = subscribe_and_join(lector_socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _

      ref = push(lector_sock, "crear", %{"titulo" => "T"})
      assert_reply ref, :error, %{"reason" => "sin_permiso"}
    end

    test "titulo vacío retorna error", %{socket: socket} do
      ref = push(socket, "crear", %{"titulo" => ""})
      assert_reply ref, :error, %{"reason" => "titulo_vacio"}
    end

    test "puntos inválidos retorna error", %{socket: socket} do
      ref = push(socket, "crear", %{"titulo" => "T", "puntos" => 4})
      assert_reply ref, :error, %{"reason" => "puntos_invalidos"}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # editar
  # ──────────────────────────────────────────────────────────────────────────

  describe "handle_in editar" do
    setup %{socket: socket, proyecto: p} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Original"})
      %{socket: socket, ticket: ticket}
    end

    test "edita el titulo", %{socket: socket, ticket: t} do
      ref = push(socket, "editar", %{"ticket_id" => t.id, "titulo" => "Editado"})
      assert_reply ref, :ok, %{ticket: ticket}
      assert ticket["titulo"] == "Editado"
      assert_broadcast "ticket_editado", %{ticket: ^ticket}
    end

    test "no puede editar ticket de otro proyecto", %{socket: socket} do
      {:ok, otro_p} = insertar_proyecto()
      {:ok, ticket_ajeno} = insertar_ticket(otro_p.id, %{titulo: "Ajeno"})

      ref = push(socket, "editar", %{"ticket_id" => ticket_ajeno.id, "titulo" => "X"})
      assert_reply ref, :error, %{"reason" => "ticket_de_otro_proyecto"}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # mover
  # ──────────────────────────────────────────────────────────────────────────

  describe "handle_in mover" do
    setup %{socket: socket, proyecto: p, usuario: u} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Para mover"})
      {:ok, ticket_asignado} = insertar_ticket(p.id, %{titulo: "Con asignado"})
      {:ok, _} = asignar_ticket(u.id, ticket_asignado.id)
      %{socket: socket, ticket: ticket, ticket_asignado: ticket_asignado}
    end

    test "mueve a resuelto y hace broadcast", %{socket: socket, ticket: t} do
      ref = push(socket, "mover", %{"ticket_id" => t.id, "estado" => "resuelto"})
      assert_reply ref, :ok, %{ticket: ticket}
      assert ticket["estado"] == "resuelto"
      assert_broadcast "ticket_movido", %{ticket: ^ticket}
    end

    test "sin responsable no pasa a en_progreso", %{socket: socket, ticket: t} do
      ref = push(socket, "mover", %{"ticket_id" => t.id, "estado" => "en_progreso"})
      assert_reply ref, :error, %{"reason" => "sin_asignar"}
    end

    test "con responsable pasa a en_progreso", %{socket: socket, ticket_asignado: t} do
      ref = push(socket, "mover", %{"ticket_id" => t.id, "estado" => "en_progreso"})
      assert_reply ref, :ok, %{ticket: ticket}
      assert ticket["estado"] == "en_progreso"
    end

    test "ticket cerrado no puede moverse", %{socket: socket, ticket: t} do
      ref_cerrar = push(socket, "mover", %{"ticket_id" => t.id, "estado" => "cerrado"})
      assert_reply ref_cerrar, :ok, _

      ref = push(socket, "mover", %{"ticket_id" => t.id, "estado" => "abierto"})
      assert_reply ref, :error, %{"reason" => "ticket_cerrado"}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # asignar / desasignar
  # ──────────────────────────────────────────────────────────────────────────

  describe "handle_in asignar" do
    setup %{socket: socket, proyecto: p, usuario: u} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Para asignar"})
      %{socket: socket, ticket: ticket, usuario: u}
    end

    test "asigna usuario miembro y hace broadcast", %{socket: socket, ticket: t, usuario: u} do
      ref = push(socket, "asignar", %{"ticket_id" => t.id, "usuario_id" => u.id})
      assert_reply ref, :ok, %{ticket: ticket}
      assert ticket["asignado"] == u.id
      assert_broadcast "ticket_asignado", %{ticket: ^ticket}
    end

    test "no asigna a usuario externo", %{socket: socket, ticket: t} do
      {:ok, externo} = insertar_usuario()
      ref = push(socket, "asignar", %{"ticket_id" => t.id, "usuario_id" => externo.id})
      assert_reply ref, :error, %{"reason" => "usuario_no_es_miembro"}
    end
  end

  describe "handle_in desasignar" do
    setup %{socket: socket, proyecto: p, usuario: u} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Para desasignar"})
      {:ok, _} = asignar_ticket(u.id, ticket.id)
      %{socket: socket, ticket: ticket}
    end

    test "quita el responsable y hace broadcast", %{socket: socket, ticket: t} do
      ref = push(socket, "desasignar", %{"ticket_id" => t.id})
      assert_reply ref, :ok, %{ticket: ticket}
      assert is_nil(ticket["asignado"])
      assert_broadcast "ticket_asignado", %{ticket: ^ticket}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # listar / resumen
  # ──────────────────────────────────────────────────────────────────────────

  describe "handle_in listar" do
    setup %{socket: socket, proyecto: p} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      {:ok, t1} = insertar_ticket(p.id, %{titulo: "T1", prioridad: "alta"})
      {:ok, t2} = insertar_ticket(p.id, %{titulo: "T2", prioridad: "baja"})
      %{socket: socket, t1: t1, t2: t2}
    end

    test "lista todos los tickets del proyecto", %{socket: socket} do
      ref = push(socket, "listar", %{})
      assert_reply ref, :ok, %{tickets: tickets}
      assert length(tickets) == 2
    end

    test "filtra por estado", %{socket: socket, t1: t1} do
      ref_cerrar = push(socket, "mover", %{"ticket_id" => t1.id, "estado" => "cerrado"})
      assert_reply ref_cerrar, :ok, _

      ref = push(socket, "listar", %{"estado" => "abierto"})
      assert_reply ref, :ok, %{tickets: [ticket]}
      assert ticket["titulo"] == "T2"
    end
  end

  describe "handle_in resumen" do
    setup %{socket: socket, proyecto: p} do
      {:ok, _, socket} = subscribe_and_join(socket, "tablero:#{p.id}", %{})
      assert_push "tickets_iniciales", _
      %{socket: socket}
    end

    test "devuelve conteo de los 4 estados", %{socket: socket} do
      ref = push(socket, "resumen", %{})
      assert_reply ref, :ok, %{resumen: resumen}
      assert Map.has_key?(resumen, "abierto")
      assert Map.has_key?(resumen, "en_progreso")
      assert Map.has_key?(resumen, "resuelto")
      assert Map.has_key?(resumen, "cerrado")
    end
  end
end
