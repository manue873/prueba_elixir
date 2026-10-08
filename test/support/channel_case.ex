defmodule PruebaElixirWeb.ChannelCase do
  @moduledoc """
  Caso base para tests de channels: importa `Phoenix.ChannelTest` y fija el
  endpoint de la app.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import PruebaElixirWeb.ChannelCase

      @endpoint PruebaElixirWeb.Endpoint
    end
  end
end
