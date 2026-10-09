defmodule PruebaElixirWeb.PingChannelTest do
  use PruebaElixirWeb.ChannelCase, async: true

  alias PruebaElixirWeb.{PingChannel, UserSocket}

  setup do
    # UserSocket ahora valida usuario_id contra SurrealDB.
    # Para tests unitarios del canal usamos socket/3 que crea un socket con
    # assigns prefijados, saltando el connect/2 (sin necesitar la DB).
    socket = socket(UserSocket, "test_socket", %{usuario_id: "test_user"})
    {:ok, _reply, socket} = subscribe_and_join(socket, PingChannel, "ping")

    %{socket: socket}
  end

  test "responde pong a ping", %{socket: socket} do
    ref = push(socket, "ping", %{})

    assert_reply ref, :ok, %{message: "pong"}
  end

  test "el socket enruta el topic ping al PingChannel" do
    socket = socket(UserSocket, "test_socket_2", %{usuario_id: "test_user"})

    assert {:ok, _reply, %Phoenix.Socket{channel: PingChannel, topic: "ping"}} =
             subscribe_and_join(socket, "ping", %{})
  end
end
