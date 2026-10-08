defmodule PruebaElixir.Surreal.Config do
  @moduledoc """
  Configuración validada del cliente SurrealDB.

  Los valores salen de `config :prueba_elixir, :surrealdb` (ver
  `config/runtime.exs`); cada llamada puede sobreescribirlos con `opts`.
  """

  @app :prueba_elixir
  @default_url "http://127.0.0.1:8030"
  @default_namespace "prueba_elixir"
  @default_database "dev"
  @default_timeout 15_000

  @typedoc "Opciones normalizadas que consume `PruebaElixir.Surreal.Client`."
  @type t :: %{
          url: String.t(),
          namespace: String.t() | nil,
          database: String.t() | nil,
          username: String.t() | nil,
          password: String.t() | nil,
          token: String.t() | nil,
          auth_level: :auto | :root | :namespace | :database,
          timeout: pos_integer(),
          recv_timeout: pos_integer(),
          http_client: atom(),
          session_auth: boolean()
        }

  @spec load(keyword()) :: t()
  def load(opts \\ []) when is_list(opts) do
    app_config = Application.get_env(@app, :surrealdb, [])

    %{
      url: trim_trailing_slash(option(opts, app_config, :url, @default_url)),
      namespace: option(opts, app_config, :namespace, @default_namespace),
      database: option(opts, app_config, :database, @default_database),
      username: option(opts, app_config, :username, nil),
      password: option(opts, app_config, :password, nil),
      token: option(opts, app_config, :token, nil),
      auth_level: auth_level(option(opts, app_config, :auth_level, :auto)),
      timeout: option(opts, app_config, :timeout, @default_timeout),
      recv_timeout: option(opts, app_config, :recv_timeout, @default_timeout),
      http_client: option(opts, app_config, :http_client, :httpc),
      session_auth: option(opts, app_config, :session_auth, false)
    }
    |> validate!()
  end

  @spec validate!(t()) :: t()
  def validate!(config) when is_map(config) do
    config
    |> validate_url!()
    |> validate_scope!(:namespace)
    |> validate_scope!(:database)
    |> validate_credentials!()
    |> validate_timeout!(:timeout)
    |> validate_timeout!(:recv_timeout)
    |> validate_http_client!()
    |> validate_session_auth!()
  end

  def validate!(_config), do: raise(ArgumentError, "SurrealDB config must be a map")

  defp validate_url!(config) do
    url = Map.get(config, :url)
    uri = if is_binary(url), do: URI.parse(url), else: nil

    if is_binary(url) and uri.scheme in ["http", "https"] and is_binary(uri.host) and
         uri.host != "" do
      config
    else
      raise ArgumentError, "SurrealDB url must be an absolute http(s) URL"
    end
  end

  defp validate_scope!(config, key) do
    case Map.get(config, key) do
      nil -> config
      value when is_binary(value) and value != "" -> config
      _value -> raise ArgumentError, "SurrealDB #{key} must be a non-empty string or nil"
    end
  end

  defp validate_credentials!(config) do
    username = Map.get(config, :username)
    password = Map.get(config, :password)
    token = Map.get(config, :token)

    valid_token? = is_nil(token) or (is_binary(token) and token != "")

    valid_basic? =
      (is_nil(username) and is_nil(password)) or
        (is_binary(username) and username != "" and is_binary(password))

    if valid_token? and valid_basic? do
      config
    else
      raise ArgumentError,
            "SurrealDB credentials must be a bearer token or a username/password pair"
    end
  end

  defp validate_timeout!(config, key) do
    case Map.get(config, key) do
      value when is_integer(value) and value > 0 -> config
      _value -> raise ArgumentError, "SurrealDB #{key} must be a positive integer"
    end
  end

  defp validate_http_client!(config) do
    if is_atom(Map.get(config, :http_client)) do
      config
    else
      raise ArgumentError, "SurrealDB http_client must be a module or :httpc"
    end
  end

  defp validate_session_auth!(config) do
    if is_boolean(Map.get(config, :session_auth)) do
      config
    else
      raise ArgumentError, "SurrealDB session_auth must be a boolean"
    end
  end

  defp option(opts, app_config, key, default) do
    case nested_option(opts, key) do
      :missing -> Keyword.get(opts, key, Keyword.get(app_config, key, default))
      value -> value
    end
  end

  defp nested_option(opts, key) do
    case Keyword.get(opts, :surreal_options, :missing) do
      nested when is_list(nested) -> Keyword.get(nested, key, :missing)
      _ -> :missing
    end
  end

  defp auth_level(level) when level in [:auto, :root, :namespace, :database], do: level

  defp auth_level(level) when is_binary(level) do
    case String.downcase(String.trim(level)) do
      "root" -> :root
      "namespace" -> :namespace
      "ns" -> :namespace
      "database" -> :database
      "db" -> :database
      "auto" -> :auto
      _ -> raise ArgumentError, "SurrealDB auth_level must be auto, root, namespace, or database"
    end
  end

  defp auth_level(_level),
    do: raise(ArgumentError, "SurrealDB auth_level must be auto, root, namespace, or database")

  defp trim_trailing_slash(url) when is_binary(url), do: String.trim_trailing(url, "/")
  defp trim_trailing_slash(url), do: url
end
