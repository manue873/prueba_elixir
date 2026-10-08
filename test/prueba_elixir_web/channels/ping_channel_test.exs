defmodule PruebaElixirWeb.PingChannelTest do
  use PruebaElixirWeb.ChannelCase, async: true

  alias PruebaElixirWeb.{PingChannel, UserSocket}

  setup do
    {:ok, socket} = connect(UserSocket, %{})
    {:ok, _reply, socket} = subscribe_and_join(socket, PingChannel, "ping")

    %{socket: socket}
  end

  test "responde pong a ping", %{socket: socket} do
    ref = push(socket, "ping", %{})

    assert_reply ref, :ok, %{message: "pong"}
  end

  test "el socket enruta el topic ping al PingChannel" do
    {:ok, socket} = connect(UserSocket, %{})

    assert {:ok, _reply, %Phoenix.Socket{channel: PingChannel, topic: "ping"}} =
             subscribe_and_join(socket, "ping", %{})
  end
end
