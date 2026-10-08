defmodule PruebaElixir.Surreal.HttpcPool do
  @moduledoc """
  Perfil propio de `:httpc` que usan todas las peticiones a SurrealDB.

  El perfil por defecto de httpc solo mantiene dos conexiones persistentes por
  host; con un perfil dedicado se dimensiona el pool solo para SurrealDB sin
  tocar el perfil que comparten otras librerías.

  Opciones, leídas de `config :prueba_elixir, :surrealdb`:

    * `:max_sessions` - conexiones persistentes por host (por defecto 32)
    * `:max_keep_alive_length` - peticiones que pueden esperar detrás de la que
      está en curso en una conexión (por defecto 0: solo se reutiliza una
      conexión libre, así ninguna petición espera la respuesta de otra).
  """

  @profile :prueba_elixir_surreal
  @default_max_sessions 32
  @default_max_keep_alive_length 0
  @started_key {__MODULE__, :started}

  @spec profile() :: atom()
  def profile, do: @profile

  @doc """
  Envía una petición por el perfil de SurrealDB, arrancándolo en el primer uso.
  Si el perfil desapareció (se reinició inets), lo arranca de nuevo y reenvía
  la petición una vez.
  """
  @spec request(atom(), tuple(), keyword(), keyword()) :: term()
  def request(method, request, http_options, options) do
    with :ok <- ensure_started() do
      case send_request(method, request, http_options, options) do
        :profile_down ->
          :persistent_term.erase(@started_key)

          with :ok <- ensure_started() do
            case send_request(method, request, http_options, options) do
              :profile_down -> {:error, {:httpc_profile_unavailable, @profile}}
              result -> result
            end
          end

        result ->
          result
      end
    end
  end

  @doc "Arranca el perfil una vez por nodo y aplica los límites configurados."
  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    if :persistent_term.get(@started_key, false), do: :ok, else: start()
  end

  @doc "Arranca el perfil si hace falta y (re)aplica los límites configurados."
  @spec start() :: :ok | {:error, term()}
  def start do
    with {:ok, _apps} <- Application.ensure_all_started(:inets),
         :ok <- start_profile(),
         :ok <- :httpc.set_options(options(), @profile) do
      :persistent_term.put(@started_key, true)
      :ok
    end
  end

  @doc "Límites aplicados al perfil, leídos de la configuración de la app."
  @spec options() :: keyword()
  def options do
    config = Application.get_env(:prueba_elixir, :surrealdb, [])

    [
      max_sessions: positive(config, :max_sessions, @default_max_sessions),
      max_keep_alive_length:
        non_negative(config, :max_keep_alive_length, @default_max_keep_alive_length)
    ]
  end

  defp start_profile do
    case :inets.start(:httpc, profile: @profile) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # httpc llama al proceso gestor del perfil; si el perfil no existe, la
  # llamada sale con :noproc en vez de devolver un error.
  defp send_request(method, request, http_options, options) do
    :httpc.request(method, request, http_options, options, @profile)
  catch
    :exit, {:noproc, _call} -> :profile_down
  end

  defp positive(config, key, default) do
    case Keyword.get(config, key, default) do
      value when is_integer(value) and value > 0 -> value
      other -> raise ArgumentError, "#{key} must be a positive integer, got: #{inspect(other)}"
    end
  end

  defp non_negative(config, key, default) do
    case Keyword.get(config, key, default) do
      value when is_integer(value) and value >= 0 ->
        value

      other ->
        raise ArgumentError, "#{key} must be a non-negative integer, got: #{inspect(other)}"
    end
  end
end
