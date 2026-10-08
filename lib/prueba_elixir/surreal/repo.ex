defmodule PruebaElixir.Surreal.Repo do
  @moduledoc """
  Fachada tipo Repo sobre SurrealDB.

  Acepta un módulo `PruebaElixir.Surreal.Schema` (devuelve structs) o el
  nombre de una tabla como string (devuelve mapas crudos). Tabla e id viajan
  siempre como `$table`/`$id`; el contenido de un registro (un mapa, que no
  cabe en un parámetro HTTP escalar) se escribe como literal JSON escapado.
  """

  alias PruebaElixir.Surreal.{Client, UUIDv7}

  def query(statement, params \\ %{}, opts \\ []) do
    Client.query(statement, params, opts)
  end

  def get(schema_or_table, id, opts \\ []) do
    table = table(schema_or_table)
    id = external_id(schema_or_table, id)

    # Lee un registro por id. type::record($table, $id) arma "tabla:id" desde
    # parámetros: tabla e id nunca se concatenan al texto de la sentencia.
    "SELECT * FROM type::record($table, $id);"
    |> query(%{table: table, id: id}, opts)
    |> one_result(schema_or_table)
  end

  def get!(schema_or_table, id, opts \\ []) do
    case get(schema_or_table, id, opts) do
      {:ok, nil} -> raise Client.Error, message: "SurrealDB record not found", details: %{id: id}
      {:ok, record} -> record
      {:error, error} -> raise error
    end
  end

  # La sentencia la escribe quien llama: los valores deben ir como $params.
  def all(schema_or_table, statement, params \\ %{}, opts \\ []) do
    statement
    |> query(params, opts)
    |> all_results(schema_or_table)
  end

  def transaction_insert(records, opts \\ []) when is_list(records) do
    prepared_records =
      Enum.map(records, fn {schema, attrs} ->
        attrs = stringify_keys(attrs)
        id = Map.get(attrs, "id") || UUIDv7.generate()
        {schema, id, Map.put(attrs, "id", id)}
      end)

    statement =
      prepared_records
      |> Enum.map_join("\n", fn {schema, _id, attrs} -> transaction_create(schema, attrs) end)

    with {:ok, _results} <- transaction(statement, opts) do
      {:ok, Enum.map(prepared_records, fn {schema, id, _attrs} -> {schema, id} end)}
    end
  end

  def transaction_update(records, opts \\ [])

  def transaction_update([], _opts), do: {:ok, []}

  def transaction_update(records, opts) when is_list(records) do
    statement =
      records
      |> Enum.map_join("\n", fn {schema, id, attrs} ->
        transaction_update(schema, id, attrs)
      end)

    with {:ok, _results} <- transaction(statement, opts) do
      {:ok, Enum.map(records, fn {schema, id, _attrs} -> {schema, id} end)}
    end
  end

  def insert(struct_or_schema, attrs_or_opts \\ [], opts \\ [])

  def insert(%schema{} = struct, opts, repo_opts)
      when is_list(opts) and is_list(repo_opts) do
    attrs = schema.to_surreal(struct)
    insert(schema, attrs, repo_opts)
  end

  def insert(schema_or_table, attrs, opts) when is_map(attrs) do
    table = table(schema_or_table)
    attrs = stringify_keys(attrs)
    id = Map.get(attrs, "id") || UUIDv7.generate()
    attrs = persistable_attrs(attrs)
    content = content_literal(attrs, schema_or_table)

    # Crea el registro "tabla:id". Tabla e id van como $params; CONTENT es un
    # literal porque un mapa no cabe en un parámetro HTTP (solo escalares) y
    # cada clave/valor sale de Jason.encode!/1, así que llega escapado.
    """
    CREATE type::record($table, $id) CONTENT #{content};
    """
    |> query(%{table: table, id: id}, opts)
    |> one_result(schema_or_table)
  end

  def update(%schema{} = struct, attrs) when is_map(attrs) do
    update(schema, schema.external_id(struct.id), attrs)
  end

  def update(%schema{} = struct, attrs, opts)
      when is_map(attrs) and is_list(opts) do
    update(schema, schema.external_id(struct.id), attrs, opts)
  end

  def update(schema_or_table, id, attrs, opts \\ []) when is_map(attrs) do
    table = table(schema_or_table)
    id = external_id(schema_or_table, id)
    content = attrs |> stringify_keys() |> persistable_attrs() |> content_literal(schema_or_table)

    # Fusiona (MERGE) los campos dados en el registro y devuelve el estado
    # final. Tabla e id como $params; el mapa como literal JSON escapado.
    """
    UPDATE type::record($table, $id) MERGE #{content} RETURN AFTER;
    """
    |> query(%{table: table, id: id}, opts)
    |> one_result(schema_or_table)
  end

  def delete(%schema{} = struct) do
    delete(schema, schema.external_id(struct.id))
  end

  def delete(%schema{} = struct, opts) when is_list(opts) do
    delete(schema, schema.external_id(struct.id), opts)
  end

  def delete(schema_or_table, id, opts \\ []) do
    table = table(schema_or_table)
    id = external_id(schema_or_table, id)

    # Borra el registro y devuelve cómo estaba antes (RETURN BEFORE).
    # Tabla e id como $params para no interpolar valores en la sentencia.
    "DELETE FROM type::record($table, $id) RETURN BEFORE;"
    |> query(%{table: table, id: id}, opts)
    |> one_result(schema_or_table)
  end

  def transaction(statement) when is_binary(statement) do
    transaction(statement, %{}, [])
  end

  def transaction(fun) when is_function(fun, 0) do
    {:error,
     %Client.Error{
       message: "Function transactions are not supported by the stateless SurrealDB HTTP repo"
     }}
  end

  def transaction(statement, opts) when is_binary(statement) and is_list(opts) do
    transaction(statement, %{}, opts)
  end

  def transaction(statement, params, opts) when is_binary(statement) and is_map(params) do
    statement = String.trim_trailing(statement, ";")

    # Envuelve las sentencias en una transacción: o se aplican todas o
    # ninguna. Los valores siguen llegando como $params en `params`.
    query("BEGIN TRANSACTION; #{statement}; COMMIT TRANSACTION;", params, opts)
  end

  def table(schema) when is_atom(schema) do
    Code.ensure_loaded(schema)

    if function_exported?(schema, :__surreal_table__, 0),
      do: schema.__surreal_table__(),
      else: table(to_string(schema))
  end

  def table(table) when is_binary(table), do: table

  defp external_id(schema, id) when is_atom(schema) do
    Code.ensure_loaded(schema)

    if function_exported?(schema, :external_id, 1),
      do: schema.external_id(id),
      else: id
  end

  defp external_id(_table, id), do: id

  defp one_result({:ok, [%{"result" => [record | _]} | _]}, schema_or_table) do
    {:ok, from_surreal(schema_or_table, record)}
  end

  defp one_result({:ok, [%{"result" => []} | _]}, _schema_or_table), do: {:ok, nil}
  defp one_result({:ok, [%{"result" => nil} | _]}, _schema_or_table), do: {:ok, nil}

  defp one_result({:ok, [%{"result" => record} | _]}, schema_or_table),
    do: {:ok, from_surreal(schema_or_table, record)}

  defp one_result({:error, error}, _schema_or_table), do: {:error, error}

  defp all_results({:ok, [%{"result" => records} | _]}, schema_or_table)
       when is_list(records),
       do: {:ok, Enum.map(records, &from_surreal(schema_or_table, &1))}

  defp all_results({:ok, [%{"result" => nil} | _]}, _schema_or_table), do: {:ok, []}

  defp all_results({:ok, [%{"result" => record} | _]}, schema_or_table)
       when is_map(record),
       do: {:ok, [from_surreal(schema_or_table, record)]}

  defp all_results({:ok, result}, schema_or_table) when is_list(result) do
    {:ok, Enum.flat_map(result, &result_records(&1, schema_or_table))}
  end

  defp all_results({:error, error}, _schema_or_table), do: {:error, error}

  defp result_records(%{"result" => records}, schema_or_table) when is_list(records),
    do: Enum.map(records, &from_surreal(schema_or_table, &1))

  defp result_records(_result, _schema_or_table), do: []

  # Una transacción junta varias sentencias con un solo mapa de params, así
  # que tabla e id se escriben como literales JSON escapados (Jason.encode!/1)
  # en vez de inventar un nombre de $param distinto por sentencia.
  defp transaction_create(schema, attrs) do
    table = table(schema)
    id = Map.fetch!(attrs, "id")
    content = attrs |> persistable_attrs() |> content_literal(schema)

    "CREATE type::record(#{Jason.encode!(table)}, #{Jason.encode!(id)}) CONTENT #{content};"
  end

  # Igual que transaction_create/2 pero fusionando campos (MERGE).
  defp transaction_update(schema, id, attrs) do
    table = table(schema)
    id = external_id(schema, id)
    content = attrs |> stringify_keys() |> persistable_attrs() |> content_literal(schema)

    "UPDATE type::record(#{Jason.encode!(table)}, #{Jason.encode!(id)}) MERGE #{content};"
  end

  defp from_surreal(schema, record) when is_atom(schema) do
    Code.ensure_loaded(schema)

    if function_exported?(schema, :from_surreal, 1), do: schema.from_surreal(record), else: record
  end

  defp from_surreal(_table, record), do: record

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp persistable_attrs(attrs) do
    attrs
    |> Map.delete("id")
    |> Map.delete("record_id")
  end

  # Literal de objeto SurrealQL `{"clave": valor, ...}`. Con un schema, cada
  # valor se castea según su tipo declarado (datetime, record, uuid).
  defp content_literal(attrs, schema) when is_atom(schema) do
    if function_exported?(schema, :__surreal_fields__, 0) do
      field_types =
        Map.new(schema.__surreal_fields__(), fn {name, type, opts} ->
          {to_string(name), {type, opts}}
        end)

      attrs
      |> Enum.map(fn {key, value} ->
        "#{Jason.encode!(key)}: #{value_literal(value, Map.get(field_types, key))}"
      end)
      |> Enum.join(", ")
      |> then(&"{#{&1}}")
    else
      Jason.encode!(attrs)
    end
  end

  defp content_literal(attrs, _table), do: Jason.encode!(attrs)

  # nil se guarda como NONE (campo ausente) y no como NULL.
  defp value_literal(nil, _field), do: "NONE"

  defp value_literal(%DateTime{} = value, {:datetime, _opts}) do
    "type::datetime(#{Jason.encode!(DateTime.to_iso8601(value))})"
  end

  defp value_literal(%NaiveDateTime{} = value, {:datetime, _opts}) do
    iso8601 = NaiveDateTime.to_iso8601(value) <> "Z"
    "type::datetime(#{Jason.encode!(iso8601)})"
  end

  defp value_literal(value, {:datetime, _opts}) when is_binary(value) do
    "type::datetime(#{Jason.encode!(value)})"
  end

  defp value_literal(value, {:record, opts}) when is_binary(value) do
    table = Keyword.fetch!(opts, :table)
    id = value |> String.replace_prefix("#{table}:", "") |> strip_surreal_record_quotes()

    "type::record(#{Jason.encode!(table)}, #{Jason.encode!(id)})"
  end

  defp value_literal(value, {type, _opts}) when is_binary(value) do
    if type in [:uuid, :binary_id, UUIDv7.Type] do
      "<uuid> #{Jason.encode!(value)}"
    else
      Jason.encode!(value)
    end
  end

  defp value_literal(value, _field), do: Jason.encode!(value)

  defp strip_surreal_record_quotes("`" <> id), do: String.trim_trailing(id, "`")
  defp strip_surreal_record_quotes(id), do: id
end
