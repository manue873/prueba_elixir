defmodule PruebaElixir.Surreal.Client do
  @moduledoc """
  Cliente HTTP mínimo de SurrealDB (endpoints `/sql` y `/health`).

  Cada sentencia viaja como cuerpo de `POST /sql`; los parámetros viajan
  aparte, en la query string, y SurrealDB los expone como variables `$nombre`.
  Así un valor nunca se interpreta como SurrealQL (no hay inyección).
  """

  defmodule Error do
    @moduledoc "Error de transporte, HTTP o de sentencia devuelto por SurrealDB."

    defexception [:message, :status, :details]

    def message(%__MODULE__{message: message, status: nil, details: nil}), do: message

    def message(%__MODULE__{} = error) do
      [
        error.message,
        status_message(error.status),
        details_message(error.details)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" - ")
    end

    defp status_message(nil), do: nil
    defp status_message(status), do: "status=#{status}"

    defp details_message(nil), do: nil
    defp details_message(%{"result" => result}) when is_binary(result), do: result
    defp details_message(details) when is_binary(details), do: details
    defp details_message(details), do: inspect(details)
  end

  defimpl String.Chars, for: Error do
    def to_string(error), do: Exception.message(error)
  end

  alias PruebaElixir.Surreal.{Config, HttpcPool, Session}

  @type result :: {:ok, list()} | {:error, Error.t()}

  @transaction_retry_delays [25, 75]

  def health(opts \\ []) do
    request(:get, "/health", "", %{}, opts)
  end

  @doc """
  Ejecuta `statement` (una o varias sentencias SurrealQL) con `params` como
  variables `$clave`. Devuelve la lista cruda de resultados, uno por sentencia.
  """
  def query(statement, params \\ %{}, opts \\ [])
      when is_binary(statement) and is_map(params) and is_list(opts) do
    retry_delays = Keyword.get(opts, :retry_delays, @transaction_retry_delays)
    validate_retry_delays!(retry_delays)
    query_with_retry(statement, params, opts, retry_delays)
  end

  def query!(statement, params \\ %{}, opts \\ []) do
    case query(statement, params, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp request(method, path, body, params, opts) do
    config = Config.load(opts)
    http = Keyword.get(opts, :http_client, config.http_client)

    with :ok <- ensure_http_started(http) do
      case session_token(config, http) do
        {:ok, token} ->
          case request_once(method, path, body, params, http, %{config | token: token}) do
            {:error, %Error{status: 401}} ->
              # El servidor ya no acepta este token (expirado, revocado o
              # reiniciado): se vuelve a hacer signin una vez y luego Basic.
              Session.invalidate(config)

              case session_token(config, http) do
                {:ok, fresh} when fresh != token ->
                  method
                  |> request_once(path, body, params, http, %{config | token: fresh})
                  |> fallback_to_basic(method, path, body, params, http, config)

                _no_new_token ->
                  basic_request(method, path, body, params, http, config)
              end

            result ->
              result
          end

        :none ->
          basic_request(method, path, body, params, http, config)
      end
    end
  end

  defp basic_request(method, path, body, params, http, config) do
    method
    |> request_once(path, body, params, http, config)
    |> maybe_retry_auth(method, path, body, params, http, config)
  end

  defp fallback_to_basic({:error, %Error{status: 401}}, method, path, body, params, http, config) do
    Session.invalidate(config)
    basic_request(method, path, body, params, http, config)
  end

  defp fallback_to_basic(result, _method, _path, _body, _params, _http, _config), do: result

  # El token de sesión solo reemplaza a Basic con usuario/contraseña; un
  # bearer token explícito o el acceso anónimo se usan tal como se configuran.
  defp session_token(%{session_auth: true, token: nil, username: username} = config, http)
       when is_binary(username) and username != "" do
    case Session.token(config, http) do
      {:ok, token} -> {:ok, token}
      :error -> :none
    end
  end

  defp session_token(_config, _http), do: :none

  # Reintenta solo los conflictos de transacción que SurrealDB marca como
  # reintentables, con las esperas de `:retry_delays` (ms).
  defp query_with_retry(statement, params, opts, [delay | remaining_delays]) do
    case request(:post, "/sql", statement, params, opts) do
      {:error, %Error{} = error} = result ->
        if retryable_transaction_conflict?(error) do
          Process.sleep(delay)
          query_with_retry(statement, params, opts, remaining_delays)
        else
          result
        end

      result ->
        result
    end
  end

  defp query_with_retry(statement, params, opts, []),
    do: request(:post, "/sql", statement, params, opts)

  defp request_once(method, path, body, params, http, config) do
    url = config.url <> path <> query_string(params)
    headers = headers(config)

    http
    |> request_http(method, url, body, headers, config)
    |> decode_response()
  end

  defp maybe_retry_auth(
         {:error, %Error{status: 401}} = error,
         method,
         path,
         body,
         params,
         http,
         %{
           auth_level: :auto
         } = config
       ) do
    config
    |> auth_retry_levels()
    |> Enum.reduce_while(error, fn auth_level, _last_error ->
      result = request_once(method, path, body, params, http, %{config | auth_level: auth_level})

      case result do
        {:error, %Error{status: 401}} -> {:cont, result}
        _ -> {:halt, result}
      end
    end)
  end

  defp maybe_retry_auth(result, _method, _path, _body, _params, _http, _config), do: result

  defp retryable_transaction_conflict?(%Error{
         status: 200,
         details: %{"result" => result}
       })
       when is_binary(result) do
    normalized = String.downcase(result)

    String.contains?(normalized, "transaction conflict") and
      (String.contains?(normalized, "transaction can be retried") or
         String.contains?(normalized, "retry the transaction"))
  end

  defp retryable_transaction_conflict?(_error), do: false

  defp auth_retry_levels(%{token: token}) when is_binary(token) and token != "", do: []
  defp auth_retry_levels(%{username: username}) when username in [nil, ""], do: []
  defp auth_retry_levels(_config), do: [:database, :namespace]

  defp ensure_http_started(:httpc) do
    case HttpcPool.ensure_started() do
      :ok -> :ok
      {:error, reason} -> {:error, error("Could not start HTTP client", nil, reason)}
    end
  end

  defp ensure_http_started(_http), do: :ok

  defp request_http(:httpc, :get, url, _body, headers, config) do
    safe_request(fn ->
      HttpcPool.request(
        :get,
        {String.to_charlist(url), native_headers(headers)},
        native_timeout_opts(config),
        body_format: :binary
      )
    end)
  end

  defp request_http(:httpc, :post, url, body, headers, config) do
    safe_request(fn ->
      HttpcPool.request(
        :post,
        {String.to_charlist(url), native_headers(headers), ~c"text/plain", body},
        native_timeout_opts(config),
        body_format: :binary
      )
    end)
  end

  defp request_http(http, :get, url, _body, headers, config) do
    safe_request(fn -> apply(http, :get, [url, headers, timeout_opts(config)]) end)
  end

  defp request_http(http, :post, url, body, headers, config) do
    safe_request(fn -> apply(http, :post, [url, body, headers, timeout_opts(config)]) end)
  end

  defp native_headers(headers) do
    Enum.map(headers, fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  defp native_timeout_opts(config) do
    [connect_timeout: config.timeout, timeout: config.recv_timeout]
  end

  defp decode_response({:ok, {{_version, status, _reason}, _headers, body}}) do
    decode_response({:ok, %{status_code: status, body: body}})
  end

  defp decode_response({:ok, %{status_code: status, body: body}}) when status in 200..299 do
    case decode_body(body) do
      {:ok, results} when is_list(results) ->
        decode_results(results, status)

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, error("SurrealDB returned invalid JSON", status, reason)}
    end
  end

  defp decode_response({:ok, %{status_code: status, body: body}}) do
    {:error, error("SurrealDB HTTP request failed", status, error_body(body))}
  end

  defp decode_response({:error, %{reason: reason}}) do
    {:error, error("Could not connect to SurrealDB", nil, reason)}
  end

  defp decode_response({:error, reason}) do
    {:error, error("Could not connect to SurrealDB", nil, reason)}
  end

  defp decode_response(response) do
    {:error, error("SurrealDB HTTP client returned an invalid response", nil, response)}
  end

  defp decode_body(body) when body in [nil, ""], do: {:ok, []}

  defp decode_body(body) when is_binary(body) do
    Jason.decode(body)
  end

  defp decode_body(body) when is_map(body) or is_list(body), do: {:ok, body}
  defp decode_body(body), do: {:error, {:unsupported_body, body}}

  # SurrealDB responde 200 aunque una sentencia falle: el error va en el
  # "status" de cada resultado, así que se revisan todos.
  defp decode_results(results, status) do
    if Enum.all?(results, &is_map/1) do
      case Enum.find(results, &(Map.get(&1, "status") not in [nil, "OK"])) do
        nil -> {:ok, results}
        error -> {:error, error("SurrealDB query failed", status, error)}
      end
    else
      {:error, error("SurrealDB returned an invalid result list", status, results)}
    end
  end

  defp error_body(body) do
    case decode_body(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  defp error(message, status, details) do
    %Error{message: message, status: status, details: details}
  end

  defp headers(config) do
    [
      {"accept", "application/json"},
      {"content-type", "text/plain"},
      {"surreal-ns", config.namespace},
      {"surreal-db", config.database}
    ]
    |> reject_blank_headers()
    |> maybe_auth(config)
  end

  defp maybe_auth(headers, %{token: token}) when is_binary(token) and token != "" do
    [{"authorization", "Bearer #{token}"} | headers]
  end

  defp maybe_auth(headers, %{username: username, password: password} = config)
       when is_binary(username) and username != "" and is_binary(password) do
    encoded = Base.encode64("#{username}:#{password}")

    [{"authorization", "Basic #{encoded}"} | auth_scope_headers(headers, config)]
    |> reject_blank_headers()
  end

  defp maybe_auth(headers, _config), do: headers

  defp auth_scope_headers(headers, %{auth_level: :database} = config) do
    [{"surreal-auth-ns", config.namespace}, {"surreal-auth-db", config.database} | headers]
  end

  defp auth_scope_headers(headers, %{auth_level: :namespace} = config) do
    [{"surreal-auth-ns", config.namespace} | headers]
  end

  defp auth_scope_headers(headers, _config), do: headers

  defp reject_blank_headers(headers) do
    Enum.reject(headers, fn {_key, value} -> value in [nil, ""] end)
  end

  # Los params van en la URL (?clave=valor) y SurrealDB los publica como
  # `$clave` dentro de la sentencia. Por eso solo se aceptan escalares, y
  # llegan como string: un número o fecha se castea en la sentencia
  # (`type::int($x)`, `type::datetime($x)`).
  defp query_string(params) when map_size(params) == 0, do: ""

  defp query_string(params) do
    params =
      params
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, value} -> {to_string(key), binding_param!(value)} end)

    "?" <> URI.encode_query(params)
  end

  defp binding_param!(value) when is_binary(value), do: value
  defp binding_param!(value) when is_integer(value), do: Integer.to_string(value)
  defp binding_param!(value) when is_float(value), do: Float.to_string(value)
  defp binding_param!(value) when is_boolean(value), do: to_string(value)
  defp binding_param!(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp binding_param!(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp binding_param!(value) do
    raise ArgumentError, "SurrealDB HTTP query params must be scalar, got: #{inspect(value)}"
  end

  defp timeout_opts(config) do
    [timeout: config.timeout, recv_timeout: config.recv_timeout]
  end

  defp safe_request(fun) do
    fun.()
  rescue
    exception -> {:error, %{reason: {:exception, exception}}}
  catch
    kind, reason -> {:error, %{reason: {kind, reason}}}
  end

  defp validate_retry_delays!(delays) when is_list(delays) do
    if Enum.all?(delays, &(is_integer(&1) and &1 >= 0)) do
      :ok
    else
      raise ArgumentError, "SurrealDB retry_delays must contain non-negative integers"
    end
  end

  defp validate_retry_delays!(_delays),
    do: raise(ArgumentError, "SurrealDB retry_delays must be a list")
end
