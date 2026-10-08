defmodule PruebaElixir.TableroTest do
  @moduledoc "Tests de integración del contexto Tablero contra SurrealDB real."

  use PruebaElixirWeb.SurrealCase, async: false

  @moduletag :surreal

  alias PruebaElixir.Tablero

  setup do
    {:ok, usuario} = insertar_usuario(%{activo: true})
    {:ok, lector} = insertar_usuario(%{email: "lector@nexora.io", activo: true})
    {:ok, inactivo} = insertar_usuario(%{email: "inactivo@nexora.io", activo: false})
    {:ok, proyecto} = insertar_proyecto()

    {:ok, _} = insertar_miembro(usuario.id, proyecto.id, "desarrollador")
    {:ok, _} = insertar_miembro(lector.id, proyecto.id, "lector")

    %{
      usuario: usuario,
      lector: lector,
      inactivo: inactivo,
      proyecto: proyecto
    }
  end

  # ────────────────────────────────────────────────────────────────────────
  # usuario_activo/1
  # ────────────────────────────────────────────────────────────────────────

  describe "usuario_activo/1" do
    test "usuario activo retorna {:ok, usuario}", %{usuario: u} do
      assert {:ok, %{id: id}} = Tablero.usuario_activo(u.id)
      assert id == u.id
    end

    test "usuario inactivo retorna error", %{inactivo: u} do
      assert {:error, :usuario_invalido} = Tablero.usuario_activo(u.id)
    end

    test "usuario inexistente retorna error" do
      assert {:error, :usuario_invalido} = Tablero.usuario_activo("no-existe")
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # membresía/2
  # ────────────────────────────────────────────────────────────────────────

  describe "membresía/2" do
    test "miembro activo retorna rol", %{usuario: u, proyecto: p} do
      assert {:ok, %{rol: "desarrollador"}} = Tablero.membresía(u.id, p.id)
    end

    test "usuario inactivo NO tiene membresía", %{inactivo: u, proyecto: p} do
      {:ok, _} = insertar_miembro(u.id, p.id, "desarrollador")
      assert {:error, :sin_acceso} = Tablero.membresía(u.id, p.id)
    end

    test "usuario no miembro retorna sin_acceso", %{proyecto: p} do
      {:ok, otro} = insertar_usuario()
      assert {:error, :sin_acceso} = Tablero.membresía(otro.id, p.id)
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # crear_ticket/3
  # ────────────────────────────────────────────────────────────────────────

  describe "crear_ticket/3" do
    test "desarrollador puede crear ticket", %{proyecto: p} do
      assert {:ok, ticket} =
               Tablero.crear_ticket(p.id, "desarrollador", %{"titulo" => "Nuevo"})

      assert ticket.titulo == "Nuevo"
      assert ticket.estado == "abierto"
      assert ticket.prioridad == "media"
      assert ticket.proyecto == p.id
    end

    test "lector NO puede crear", %{proyecto: p} do
      assert {:error, :sin_permiso} =
               Tablero.crear_ticket(p.id, "lector", %{"titulo" => "T"})
    end

    test "titulo requerido" do
      {:ok, p} = insertar_proyecto()
      assert {:error, :titulo_requerido} = Tablero.crear_ticket(p.id, "lider", %{})
    end

    test "prioridad inválida" do
      {:ok, p} = insertar_proyecto()

      assert {:error, :prioridad_invalida} =
               Tablero.crear_ticket(p.id, "lider", %{"titulo" => "T", "prioridad" => "mala"})
    end

    test "puntos de Fibonacci son válidos", %{proyecto: p} do
      for pts <- [1, 2, 3, 5, 8, 13] do
        assert {:ok, t} =
                 Tablero.crear_ticket(p.id, "lider", %{"titulo" => "T#{pts}", "puntos" => pts})

        assert t.puntos == pts
      end
    end

    test "puntos inválidos son rechazados", %{proyecto: p} do
      assert {:error, :puntos_invalidos} =
               Tablero.crear_ticket(p.id, "lider", %{"titulo" => "T", "puntos" => 4})
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # editar_ticket/4
  # ────────────────────────────────────────────────────────────────────────

  describe "editar_ticket/4" do
    setup %{proyecto: p} do
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Original"})
      %{ticket: ticket}
    end

    test "edita titulo", %{proyecto: p, ticket: t} do
      assert {:ok, editado} = Tablero.editar_ticket(p.id, t.id, "lider", %{"titulo" => "Nuevo"})
      assert editado.titulo == "Nuevo"
    end

    test "lector no puede editar", %{proyecto: p, ticket: t} do
      assert {:error, :sin_permiso} =
               Tablero.editar_ticket(p.id, t.id, "lector", %{"titulo" => "X"})
    end

    test "no puede editar ticket de otro proyecto", %{ticket: t} do
      {:ok, otro_proyecto} = insertar_proyecto()

      assert {:error, :ticket_de_otro_proyecto} =
               Tablero.editar_ticket(otro_proyecto.id, t.id, "lider", %{"titulo" => "X"})
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # mover_ticket/4
  # ────────────────────────────────────────────────────────────────────────

  describe "mover_ticket/4" do
    setup %{proyecto: p, usuario: u} do
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Para mover"})
      {:ok, ticket_con_asignado} = insertar_ticket(p.id, %{titulo: "Con asignado"})
      {:ok, _} = asignar_ticket(u.id, ticket_con_asignado.id)
      %{ticket: ticket, ticket_con_asignado: ticket_con_asignado}
    end

    test "puede mover a resuelto sin responsable", %{proyecto: p, ticket: t} do
      assert {:ok, movido} = Tablero.mover_ticket(p.id, t.id, "lider", "resuelto")
      assert movido.estado == "resuelto"
    end

    test "no puede mover a en_progreso sin responsable", %{proyecto: p, ticket: t} do
      assert {:error, :sin_asignar} = Tablero.mover_ticket(p.id, t.id, "lider", "en_progreso")
    end

    test "puede mover a en_progreso con responsable", %{
      proyecto: p,
      ticket_con_asignado: t
    } do
      assert {:ok, movido} = Tablero.mover_ticket(p.id, t.id, "lider", "en_progreso")
      assert movido.estado == "en_progreso"
    end

    test "cerrado es definitivo", %{proyecto: p, ticket: t} do
      {:ok, _} = Tablero.mover_ticket(p.id, t.id, "lider", "cerrado")
      assert {:error, :ticket_cerrado} = Tablero.mover_ticket(p.id, t.id, "lider", "abierto")
    end

    test "lector no puede mover", %{proyecto: p, ticket: t} do
      assert {:error, :sin_permiso} = Tablero.mover_ticket(p.id, t.id, "lector", "resuelto")
    end

    test "ticket de otro proyecto bloqueado", %{ticket: t} do
      {:ok, otro} = insertar_proyecto()
      assert {:error, :ticket_de_otro_proyecto} = Tablero.mover_ticket(otro.id, t.id, "lider", "resuelto")
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # asignar_ticket/4 y desasignar_ticket/3
  # ────────────────────────────────────────────────────────────────────────

  describe "asignar_ticket/4" do
    setup %{proyecto: p, usuario: u} do
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Para asignar"})
      %{ticket: ticket, usuario: u}
    end

    test "asigna un miembro activo", %{proyecto: p, ticket: t, usuario: u} do
      assert {:ok, ticket} = Tablero.asignar_ticket(p.id, t.id, u.id, "lider")
      assert ticket.asignado == u.id
    end

    test "lector no puede asignar", %{proyecto: p, ticket: t, usuario: u} do
      assert {:error, :sin_permiso} = Tablero.asignar_ticket(p.id, t.id, u.id, "lector")
    end

    test "no asigna a usuario no miembro", %{proyecto: p, ticket: t} do
      {:ok, externo} = insertar_usuario()
      assert {:error, :usuario_no_es_miembro} = Tablero.asignar_ticket(p.id, t.id, externo.id, "lider")
    end

    test "reemplaza al responsable anterior", %{proyecto: p, ticket: t, usuario: u, lector: l} do
      # Primero asignar al usuario
      {:ok, _} = Tablero.asignar_ticket(p.id, t.id, u.id, "lider")
      # Añadimos al lector como desarrollador para poder asignarle
      {:ok, otro} = insertar_usuario()
      {:ok, _} = insertar_miembro(otro.id, p.id, "desarrollador")
      {:ok, ticket} = Tablero.asignar_ticket(p.id, t.id, otro.id, "lider")
      assert ticket.asignado == otro.id
    end
  end

  describe "desasignar_ticket/3" do
    setup %{proyecto: p, usuario: u} do
      {:ok, ticket} = insertar_ticket(p.id, %{titulo: "Para desasignar"})
      {:ok, _} = asignar_ticket(u.id, ticket.id)
      %{ticket: ticket}
    end

    test "quita el responsable", %{proyecto: p, ticket: t} do
      assert {:ok, ticket} = Tablero.desasignar_ticket(p.id, t.id, "lider")
      assert is_nil(ticket.asignado)
    end

    test "lector no puede desasignar", %{proyecto: p, ticket: t} do
      assert {:error, :sin_permiso} = Tablero.desasignar_ticket(p.id, t.id, "lector")
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # listar_tickets/2 y resumen/1
  # ────────────────────────────────────────────────────────────────────────

  describe "listar_tickets/2" do
    test "ordena por prioridad y fecha", %{proyecto: p} do
      {:ok, _} = insertar_ticket(p.id, %{titulo: "Baja", prioridad: "baja"})
      {:ok, _} = insertar_ticket(p.id, %{titulo: "Critica", prioridad: "critica"})
      {:ok, _} = insertar_ticket(p.id, %{titulo: "Alta", prioridad: "alta"})

      assert {:ok, [t1, t2, t3]} = Tablero.listar_tickets(p.id)
      assert t1.prioridad == "critica"
      assert t2.prioridad == "alta"
      assert t3.prioridad == "baja"
    end

    test "filtra por estado", %{proyecto: p} do
      {:ok, _} = insertar_ticket(p.id, %{titulo: "Abierto"})
      {:ok, t_cerrado} = insertar_ticket(p.id, %{titulo: "Cerrado"})
      PruebaElixir.Tablero.Queries.mover_ticket(t_cerrado.id, "cerrado")

      assert {:ok, [abierto]} = Tablero.listar_tickets(p.id, %{estado: "abierto"})
      assert abierto.titulo == "Abierto"
    end

    test "tickets no incluyen los de otros proyectos", %{proyecto: p} do
      {:ok, otro_p} = insertar_proyecto()
      {:ok, _} = insertar_ticket(p.id, %{titulo: "Del proyecto"})
      {:ok, _} = insertar_ticket(otro_p.id, %{titulo: "De otro proyecto"})

      assert {:ok, [uno]} = Tablero.listar_tickets(p.id)
      assert uno.titulo == "Del proyecto"
    end
  end

  describe "resumen/1" do
    test "devuelve conteos por estado con los 4 estados", %{proyecto: p} do
      {:ok, t1} = insertar_ticket(p.id, %{titulo: "T1"})
      {:ok, t2} = insertar_ticket(p.id, %{titulo: "T2"})
      PruebaElixir.Tablero.Queries.mover_ticket(t2.id, "cerrado")

      assert {:ok, resumen} = Tablero.resumen(p.id)
      assert resumen["abierto"] == 1
      assert resumen["cerrado"] == 1
      assert resumen["en_progreso"] == 0
      assert resumen["resuelto"] == 0
    end

    test "proyecto sin tickets devuelve todos en 0", %{proyecto: p} do
      assert {:ok, %{"abierto" => 0, "en_progreso" => 0, "resuelto" => 0, "cerrado" => 0}} =
               Tablero.resumen(p.id)
    end
  end
end
