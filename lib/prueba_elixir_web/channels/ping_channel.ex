defmodule PruebaElixirWeb.PingChannel do
  @moduledoc """
  Channel mínimo de humo: se une al topic `"ping"` y responde `"pong"` a cada
  evento `"ping"`.
  """

  use PruebaElixirWeb, :channel

  @impl true
  def join("ping", _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{message: "pong"}}, socket}
  end
end
