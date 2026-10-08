defmodule PruebaElixirWeb.UserSocket do
  @moduledoc """
  Socket de Phoenix montado en `/socket` (websocket).

  El parámetro `usuario_id` es obligatorio. La conexión se rechaza si:
  - No se proporciona `usuario_id`.
  - El usuario no existe en SurrealDB.
  - El usuario tiene `activo: false`.

  El `usuario_id` verificado queda en `socket.assigns.usuario_id` y está
  disponible para todos los channels que se abran sobre este socket.
  """

  use Phoenix.Socket

  channel "tablero:*", PruebaElixirWeb.TableroChannel
  channel "ping", PruebaElixirWeb.PingChannel

  @impl true
  def connect(%{"usuario_id" => usuario_id}, socket, _connect_info)
      when is_binary(usuario_id) and usuario_id != "" do
    case PruebaElixir.Tablero.usuario_activo(usuario_id) do
      {:ok, _usuario} ->
        {:ok, assign(socket, :usuario_id, usuario_id)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.usuario_id}"
end
