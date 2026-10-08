defmodule PruebaElixir.Tablero.Policy do
  @moduledoc """
  Reglas de negocio y autorización del tablero.

  Todas las funciones son puras (sin efectos secundarios ni consultas a DB):
  reciben datos y devuelven `:ok` o `{:error, razón_átomo}`.

  El canal y el contexto `Tablero` usan estas funciones para validar antes de
  delegar a `Queries`. Los errores atómicos se convierten a strings en el canal.
  """

  @estados_validos ~w[abierto en_progreso resuelto cerrado]
  @roles_con_permiso ~w[lider desarrollador]

  # ──────────────────────────────────────────────────────────────────────────
  # Autorización por rol
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Verifica si el rol puede realizar mutaciones (crear, editar, mover, asignar).
  Los lectores solo pueden leer.
  """
  def puede_mutar?(rol) when rol in @roles_con_permiso, do: :ok
  def puede_mutar?(_rol), do: {:error, :sin_permiso}

  # ──────────────────────────────────────────────────────────────────────────
  # Transiciones de estado
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Valida la transición de estado de un ticket.

  Reglas:
  - `cerrado` es definitivo: no se puede cambiar.
  - Para pasar a `en_progreso` el ticket debe tener un responsable asignado.
  - `nuevo_estado` debe ser uno de los 4 estados válidos.
  """
  def transicion_valida?("cerrado", _nuevo_estado, _asignado),
    do: {:error, :ticket_cerrado}

  def transicion_valida?(_estado_actual, "en_progreso", nil),
    do: {:error, :sin_asignar}

  def transicion_valida?(_estado_actual, nuevo_estado, _asignado)
      when nuevo_estado in @estados_validos,
      do: :ok

  def transicion_valida?(_estado_actual, _nuevo_estado, _asignado),
    do: {:error, :estado_invalido}

  # ──────────────────────────────────────────────────────────────────────────
  # Aislamiento entre proyectos
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Verifica que el ticket pertenezca al proyecto del canal actual.
  El `ticket.proyecto` contiene el id externo del proyecto (sin el prefijo tabla).
  """
  def mismo_proyecto?(proyecto_id_ticket, proyecto_id_canal)
      when proyecto_id_ticket == proyecto_id_canal,
      do: :ok

  def mismo_proyecto?(_ticket_proyecto, _canal_proyecto),
    do: {:error, :ticket_de_otro_proyecto}

  # ──────────────────────────────────────────────────────────────────────────
  # Atributos de ticket
  # ──────────────────────────────────────────────────────────────────────────

  @prioridades_validas ~w[baja media alta critica]
  @puntos_validos [1, 2, 3, 5, 8, 13]

  @doc "Valida los atributos de creación de un ticket."
  def validar_crear(attrs) when is_map(attrs) do
    with :ok <- validar_titulo(Map.get(attrs, "titulo") || Map.get(attrs, :titulo)),
         :ok <- validar_prioridad(Map.get(attrs, "prioridad") || Map.get(attrs, :prioridad)),
         :ok <- validar_puntos(Map.get(attrs, "puntos") || Map.get(attrs, :puntos)) do
      :ok
    end
  end

  @doc "Valida los atributos de edición de un ticket (campos parciales)."
  def validar_editar(attrs) when is_map(attrs) do
    with :ok <- maybe_validar(:titulo, attrs, &validar_titulo/1),
         :ok <- maybe_validar(:prioridad, attrs, &validar_prioridad/1),
         :ok <- maybe_validar(:puntos, attrs, &validar_puntos/1) do
      :ok
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Privado
  # ──────────────────────────────────────────────────────────────────────────

  defp validar_titulo(nil), do: {:error, :titulo_requerido}
  defp validar_titulo(""), do: {:error, :titulo_vacio}
  defp validar_titulo(titulo) when is_binary(titulo), do: :ok
  defp validar_titulo(_), do: {:error, :titulo_invalido}

  defp validar_prioridad(nil), do: :ok
  defp validar_prioridad(p) when p in @prioridades_validas, do: :ok
  defp validar_prioridad(_), do: {:error, :prioridad_invalida}

  defp validar_puntos(nil), do: :ok
  defp validar_puntos(p) when is_integer(p) and p in @puntos_validos, do: :ok
  # Los puntos pueden llegar como string desde el canal (JSON)
  defp validar_puntos(p) when is_binary(p) do
    case Integer.parse(p) do
      {n, ""} when n in @puntos_validos -> :ok
      _ -> {:error, :puntos_invalidos}
    end
  end

  defp validar_puntos(_), do: {:error, :puntos_invalidos}

  defp maybe_validar(key, attrs, fun) do
    case Map.get(attrs, key) || Map.get(attrs, to_string(key)) do
      nil -> :ok
      value -> fun.(value)
    end
  end
end
