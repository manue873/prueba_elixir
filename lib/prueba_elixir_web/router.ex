defmodule PruebaElixirWeb.Router do
  use PruebaElixirWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PruebaElixirWeb do
    pipe_through :api
  end
end
