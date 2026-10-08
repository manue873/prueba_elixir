import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Cargador mínimo de .env, solo en dev y test (sin dependencias extra).
# Formato KEY=VALUE por línea; ignora líneas vacías y comentarios (#).
# Una variable ya exportada en la shell gana sobre el valor del archivo.
if config_env() in [:dev, :test] do
  dotenv = Path.expand("../.env", __DIR__)

  if File.exists?(dotenv) do
    dotenv
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = value |> String.trim() |> String.trim("\"")
          if System.get_env(key) == nil, do: System.put_env(key, value)

        _not_an_assignment ->
          :ok
      end
    end)
  end
end

# SurrealDB (PruebaElixir.Surreal.Config). Los tests usan su propia base
# (SURREALDB_DB_TEST) para no tocar los datos de desarrollo.
config :prueba_elixir, :surrealdb,
  url: System.get_env("SURREALDB_URL", "http://127.0.0.1:8030"),
  namespace: System.get_env("SURREALDB_NS", "prueba_elixir"),
  database:
    if(config_env() == :test,
      do: System.get_env("SURREALDB_DB_TEST", "test"),
      else: System.get_env("SURREALDB_DB", "dev")
    ),
  username: System.get_env("SURREALDB_USER"),
  password: System.get_env("SURREALDB_PASS"),
  auth_level: System.get_env("SURREALDB_AUTH_LEVEL", "auto")

# The secret key base is used to sign/encrypt cookies and other secrets.
# En dev y test viene del .env; en prod debe exportarse.
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

config :prueba_elixir, PruebaElixirWeb.Endpoint, secret_key_base: secret_key_base

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/prueba_elixir start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :prueba_elixir, PruebaElixirWeb.Endpoint, server: true
end

# En test el endpoint conserva el puerto de config/test.exs (no levanta servidor).
if config_env() != :test do
  config :prueba_elixir, PruebaElixirWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end

if config_env() == :prod do
  host = System.get_env("PHX_HOST") || "example.com"

  config :prueba_elixir, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :prueba_elixir, PruebaElixirWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :prueba_elixir, PruebaElixirWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :prueba_elixir, PruebaElixirWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
