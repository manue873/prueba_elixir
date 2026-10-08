defmodule PruebaElixir.Surreal.Session do
  @moduledoc """
  Reutiliza un token de `POST /signin` por juego de credenciales en vez de
  mandar la contraseña (Basic) en cada petición. Se activa con
  `session_auth: true` en la config `:surrealdb`.

  SurrealDB hashea la contraseña Basic en cada petición; un token firmado se
  verifica mucho más rápido. El token se renueva como mucho cada diez minutos
  (y un minuto antes de su `exp`) y se descarta en cuanto SurrealDB responde
  401. La clave de caché es un hash de URL, scope, usuario, contraseña y nivel
  de auth: la contraseña no se guarda. Si el signin falla, se sigue con Basic y
  no se reintenta durante un minuto.
  """

  alias PruebaElixir.Surreal.HttpcPool

  @max_lifetime_ms 600_000
  @expiry_margin_ms 60_000
  @failure_backoff_ms 60_000

  @doc "Token cacheado o nuevo para `config`, o `:error` para autenticar con Basic."
  @spec token(map(), atom()) :: {:ok, String.t()} | :error
  def token(config, http) do
    key = key(config)
    now = System.system_time(:millisecond)

    case :persistent_term.get(key, nil) do
      %{token: token, refresh_at: refresh_at} when refresh_at > now ->
        {:ok, token}

      %{token: token, expires_at: expires_at} = entry when expires_at > now ->
        # Ventana de renovación: el token sigue sirviendo mientras un proceso lo renueva.
        case single_flight(key, fn -> refresh(config, http, key, now, entry) end) do
          {:ok, fresh} -> {:ok, fresh}
          :busy -> {:ok, token}
        end

      %{failed_until: failed_until} when failed_until > now ->
        :error

      _missing_or_expired ->
        case single_flight(key, fn -> first_signin(config, http, key, now) end) do
          {:ok, _token} = found -> found
          :error -> :error
          :busy -> :error
        end
    end
  end

  @doc "Descarta el token cacheado para `config` (tras un 401 de SurrealDB)."
  @spec invalidate(map()) :: :ok
  def invalidate(config) do
    _ = :persistent_term.erase(key(config))
    :ok
  end

  @doc false
  # Mismo orden que el camino Basic: primero root, luego usuarios con scope.
  def signin_levels(%{auth_level: :auto}), do: [:root, :database, :namespace]
  def signin_levels(%{auth_level: level}), do: [level]

  defp refresh(config, http, key, now, entry) do
    case signin(config, http) do
      {:ok, token} ->
        store(key, token, now)
        {:ok, token}

      :error ->
        # Conserva el token aún válido y reintenta tras el backoff.
        :persistent_term.put(key, %{
          entry
          | refresh_at: min(now + @failure_backoff_ms, entry.expires_at)
        })

        {:ok, entry.token}
    end
  end

  defp first_signin(config, http, key, now) do
    case signin(config, http) do
      {:ok, token} ->
        store(key, token, now)
        {:ok, token}

      :error ->
        :persistent_term.put(key, %{failed_until: now + @failure_backoff_ms})
        :error
    end
  end

  # Solo un proceso por nodo hace signin a la vez; el resto recibe :busy.
  defp single_flight(key, fun) do
    lock = {{__MODULE__, key}, self()}

    if :global.set_lock(lock, [node()], 0) do
      try do
        fun.()
      after
        :global.del_lock(lock, [node()])
      end
    else
      :busy
    end
  end

  defp store(key, token, now) do
    expires_at = expires_at(token, now)
    refresh_at = max(now + 1_000, min(now + @max_lifetime_ms, expires_at - @expiry_margin_ms))
    :persistent_term.put(key, %{token: token, refresh_at: refresh_at, expires_at: expires_at})
  end

  defp signin(config, http) do
    config
    |> signin_levels()
    |> Enum.find_value(:error, fn level ->
      case request_token(config, http, level) do
        {:ok, _token} = found -> found
        :error -> nil
      end
    end)
  end

  defp request_token(config, http, level) do
    body = Jason.encode!(signin_body(config, level))
    url = config.url <> "/signin"
    headers = [{"accept", "application/json"}, {"content-type", "application/json"}]

    case post(http, url, body, headers, config) do
      {:ok, 200, response} ->
        case Jason.decode(response) do
          {:ok, %{"token" => token}} when is_binary(token) and token != "" -> {:ok, token}
          _other -> :error
        end

      _other ->
        :error
    end
  end

  defp signin_body(config, :root), do: %{"user" => config.username, "pass" => config.password}

  defp signin_body(config, :namespace),
    do: config |> signin_body(:root) |> Map.put("ns", config.namespace)

  defp signin_body(config, :database),
    do: config |> signin_body(:namespace) |> Map.put("db", config.database)

  defp post(:httpc, url, body, headers, config) do
    request = {
      String.to_charlist(url),
      Enum.map(headers, fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end),
      ~c"application/json",
      body
    }

    case HttpcPool.request(
           :post,
           request,
           [connect_timeout: config.timeout, timeout: config.recv_timeout],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _headers, response}} -> {:ok, status, response}
      other -> {:error, other}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp post(http, url, body, headers, config) do
    case http.post(url, body, headers,
           timeout: config.timeout,
           recv_timeout: config.recv_timeout
         ) do
      {:ok, %{status_code: status, body: response}} -> {:ok, status, response}
      other -> {:error, other}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # Claim `exp` del JWT (segundos), leído sin verificar: el token solo se
  # devuelve al mismo servidor que lo emitió. Si no se conoce: vida máxima.
  defp expires_at(token, now) do
    with [_header, payload, _signature] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} when is_integer(exp) <- Jason.decode(json) do
      exp * 1_000
    else
      _unknown -> now + @max_lifetime_ms + @expiry_margin_ms
    end
  end

  defp key(config) do
    identity =
      [
        config.url,
        config.namespace,
        config.database,
        config.username,
        config.password,
        config.auth_level
      ]
      |> Enum.map_join(<<0>>, &to_string/1)

    {__MODULE__, :crypto.hash(:sha256, identity)}
  end
end
