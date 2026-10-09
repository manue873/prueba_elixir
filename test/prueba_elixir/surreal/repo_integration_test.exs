defmodule PruebaElixir.Surreal.RepoIntegrationTest do
  # Integración real contra SurrealDB (docker compose up -d), sobre la base de
  # test (SURREALDB_DB_TEST). Excluido por defecto: mix test --include surreal
  use ExUnit.Case, async: false

  @moduletag :surreal

  alias PruebaElixir.Surreal.{Client, Migrator, Repo, Storage}

  defmodule Ejemplo do
    use PruebaElixir.Surreal.Schema

    surreal_schema "ejemplo" do
      field :nombre, :string
      field :cantidad, :integer
    end
  end

  setup_all do
    # Crea namespace/base de test si faltan y aplica las migraciones (idempotente).
    {:ok, _} = Storage.up()
    {:ok, _versions} = Migrator.migrate()
    :ok
  end

  setup do
    # Vacía la tabla para que cada test parta de cero.
    {:ok, _} = Repo.query("DELETE ejemplo;")
    :ok
  end

  test "la migración de ejemplo queda aplicada" do
    assert {:ok, status} = Migrator.status()

    assert Enum.any?(
             status,
             &(&1.version == 1 and &1.filename == "000000001_create_ejemplo.surql" and &1.applied?)
           )
  end

  test "insert/get/all/query sobre ejemplo" do
    assert {:ok, %Ejemplo{id: id, record_id: record_id, nombre: "uno", cantidad: 1}} =
             Repo.insert(Ejemplo, %{nombre: "uno", cantidad: 1})

    assert is_binary(id) and id != ""
    assert record_id == Ejemplo.record_id(id)

    # get/2 acepta el id externo o el record id completo.
    assert {:ok, %Ejemplo{id: ^id, nombre: "uno", cantidad: 1}} = Repo.get(Ejemplo, id)
    assert {:ok, %Ejemplo{id: ^id}} = Repo.get(Ejemplo, record_id)
    assert {:ok, nil} = Repo.get(Ejemplo, "no-existe")

    assert {:ok, %Ejemplo{id: "fijo", cantidad: 2}} =
             Repo.insert(%Ejemplo{id: "fijo", nombre: "dos", cantidad: 2})

    # all/4 con el valor del filtro como $param. Por HTTP los params llegan
    # como string, así que los no-string se castean: type::int($min).
    assert {:ok, [%Ejemplo{nombre: "uno"}, %Ejemplo{nombre: "dos"}]} =
             Repo.all(
               Ejemplo,
               "SELECT * FROM ejemplo WHERE cantidad >= type::int($min) ORDER BY cantidad ASC;",
               %{min: 1}
             )

    assert {:ok, [%Ejemplo{nombre: "dos"}]} =
             Repo.all(Ejemplo, "SELECT * FROM ejemplo WHERE nombre = $nombre;", %{nombre: "dos"})

    # query/3 devuelve el resultado crudo, uno por sentencia.
    assert {:ok, [%{"status" => "OK", "result" => [%{"total" => 2}]}]} =
             Repo.query("SELECT count() AS total FROM ejemplo GROUP ALL;")
  end

  test "update/4 y delete/3" do
    {:ok, %Ejemplo{id: id}} = Repo.insert(Ejemplo, %{nombre: "uno", cantidad: 1})

    assert {:ok, %Ejemplo{id: ^id, nombre: "uno", cantidad: 5}} =
             Repo.update(Ejemplo, id, %{cantidad: 5})

    assert {:ok, %Ejemplo{id: ^id, cantidad: 5}} = Repo.delete(Ejemplo, id)
    assert {:ok, nil} = Repo.get(Ejemplo, id)
  end

  test "SCHEMAFULL rechaza un campo con tipo incorrecto" do
    assert {:error, %Client.Error{message: "SurrealDB query failed"}} =
             Repo.insert(Ejemplo, %{nombre: "x", cantidad: "no es int"})
  end

  test "rollback revierte con .down.surql y migrate vuelve a aplicar" do
    assert {:ok, [version]} = Migrator.rollback()
    assert {:ok, status} = Migrator.status()
    assert Enum.any?(status, &(&1.version == version and not &1.applied?))

    assert {:ok, [^version]} = Migrator.migrate()
    assert {:ok, status} = Migrator.status()
    assert Enum.any?(status, &(&1.version == version and &1.applied?))
  end
end
