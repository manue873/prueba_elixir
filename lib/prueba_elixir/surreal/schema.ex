defmodule PruebaElixir.Surreal.Schema do
  @moduledoc """
  Helper mínimo para describir registros de SurrealDB como structs.

      defmodule MiApp.Ejemplo do
        use PruebaElixir.Surreal.Schema

        surreal_schema "ejemplo" do
          field :nombre, :string
          field :cantidad, :integer
        end
      end

  Genera el struct (`:id`, `:record_id` + campos) y las funciones
  `__surreal_table__/0`, `__surreal_fields__/0`, `record_id/1`,
  `external_id/1`, `to_surreal/1` y `from_surreal/1` que usa
  `PruebaElixir.Surreal.Repo`. Tipos con trato especial: `:datetime`
  (se parsea a `DateTime`), `:record` (requiere `table:`) y `:uuid`.
  """

  defmacro __using__(_opts) do
    quote do
      import PruebaElixir.Surreal.Schema
      Module.register_attribute(__MODULE__, :surreal_fields, accumulate: true)
      @before_compile PruebaElixir.Surreal.Schema
    end
  end

  defmacro surreal_schema(table, do: block) do
    quote do
      @surreal_table unquote(table)
      unquote(block)
    end
  end

  defmacro field(name, type, opts \\ []) do
    quote do
      @surreal_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  defmacro timestamps do
    quote do
      field(:inserted_at, :datetime)
      field(:updated_at, :datetime)
    end
  end

  defmacro __before_compile__(env) do
    fields =
      env.module
      |> Module.get_attribute(:surreal_fields)
      |> Enum.reverse()

    field_names = Enum.map(fields, &elem(&1, 0))

    virtual_field_names =
      fields
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :virtual, false) end)
      |> Enum.map(&elem(&1, 0))

    persisted_fields =
      Enum.reject(fields, fn {_name, _type, opts} -> Keyword.get(opts, :virtual, false) end)

    table = Module.get_attribute(env.module, :surreal_table)

    quote do
      @enforce_keys []
      defstruct [:id, :record_id | unquote(field_names)]

      def __surreal_table__, do: unquote(table)
      def __surreal_fields__, do: unquote(Macro.escape(persisted_fields))

      # Id completo de SurrealDB: "tabla:id".
      def record_id(id), do: "#{__surreal_table__()}:#{external_id(id)}"

      # Id sin el prefijo "tabla:" ni las comillas invertidas que SurrealDB
      # añade a ids no simples (p. ej. UUIDs con guiones).
      def external_id(nil), do: nil

      def external_id(id) when is_binary(id),
        do:
          id
          |> String.replace_prefix("#{__surreal_table__()}:", "")
          |> strip_surreal_record_quotes()

      def external_id(id), do: to_string(id)

      def to_surreal(%__MODULE__{} = struct) do
        struct
        |> Map.from_struct()
        |> Map.delete(:record_id)
        |> Map.drop(unquote(virtual_field_names))
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      end

      def to_surreal(attrs) when is_map(attrs) do
        Map.new(attrs, fn
          {key, value} when is_atom(key) -> {Atom.to_string(key), value}
          {key, value} -> {to_string(key), value}
        end)
      end

      def from_surreal(attrs) when is_map(attrs) do
        raw_id = Map.get(attrs, "id", Map.get(attrs, :id))

        attrs =
          Map.new([:id, :record_id | unquote(field_names)], fn key ->
            {key, Map.get(attrs, Atom.to_string(key), Map.get(attrs, key))}
          end)

        attrs =
          attrs
          |> normalize_record_fields()
          |> Map.put(:record_id, record_id(raw_id))
          |> Map.update(:id, nil, &external_id/1)

        struct(__MODULE__, attrs)
      end

      defp normalize_record_fields(attrs) do
        Enum.reduce(__surreal_fields__(), attrs, fn
          {name, :record, opts}, attrs ->
            table = Keyword.fetch!(opts, :table)
            Map.update(attrs, name, nil, &external_record_id(&1, table))

          {name, :datetime, _opts}, attrs ->
            Map.update(attrs, name, nil, &PruebaElixir.Surreal.Schema.parse_datetime!/1)

          _field, attrs ->
            attrs
        end)
      end

      defp external_record_id(nil, _table), do: nil

      defp external_record_id(id, table) when is_binary(id),
        do: id |> String.replace_prefix("#{table}:", "") |> strip_surreal_record_quotes()

      defp external_record_id(%{"tb" => record_table, "id" => id}, table)
           when record_table == table,
           do: external_record_id(id, table)

      defp external_record_id(%{tb: record_table, id: id}, table) when record_table == table,
        do: external_record_id(id, table)

      defp external_record_id(%{"id" => id}, table), do: external_record_id(id, table)
      defp external_record_id(%{id: id}, table), do: external_record_id(id, table)
      defp external_record_id(id, _table), do: to_string(id)

      defp strip_surreal_record_quotes("`" <> id), do: String.trim_trailing(id, "`")
      defp strip_surreal_record_quotes(id), do: id
    end
  end

  def parse_datetime!(nil), do: nil
  def parse_datetime!(%DateTime{} = datetime), do: datetime

  def parse_datetime!(value) when is_binary(value) do
    value = normalize_fractional_seconds(value)

    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, reason} -> raise ArgumentError, "invalid SurrealDB datetime: #{inspect(reason)}"
    end
  end

  def parse_datetime!(value),
    do: raise(ArgumentError, "invalid SurrealDB datetime: #{inspect(value)}")

  # SurrealDB devuelve nanosegundos; DateTime admite como mucho microsegundos.
  defp normalize_fractional_seconds(value) do
    case Regex.run(~r/^(.*\.\d{6})\d+(Z|[+-]\d{2}:\d{2})$/, value) do
      [_, microseconds, offset] -> microseconds <> offset
      _ -> value
    end
  end
end
