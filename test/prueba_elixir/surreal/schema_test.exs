defmodule PruebaElixir.Surreal.SchemaTest do
  # Tests puros del helper de schema: no necesitan SurrealDB.
  use ExUnit.Case, async: true

  defmodule Ejemplo do
    use PruebaElixir.Surreal.Schema

    surreal_schema "ejemplo" do
      field :nombre, :string
      field :cantidad, :integer
      field :creado_en, :datetime
      field :nota, :string, virtual: true
    end
  end

  test "record_id/1 y external_id/1 ponen y quitan el prefijo de tabla" do
    assert Ejemplo.record_id("abc") == "ejemplo:abc"
    assert Ejemplo.external_id("ejemplo:abc") == "abc"
    assert Ejemplo.external_id("ejemplo:`0192-uuid`") == "0192-uuid"
    assert Ejemplo.external_id(nil) == nil
  end

  test "from_surreal/1 arma el struct y parsea datetimes con nanosegundos" do
    record =
      Ejemplo.from_surreal(%{
        "id" => "ejemplo:abc",
        "nombre" => "uno",
        "cantidad" => 1,
        "creado_en" => "2026-10-07T21:00:00.123456789Z"
      })

    assert %Ejemplo{id: "abc", record_id: "ejemplo:abc", nombre: "uno", cantidad: 1} = record
    assert record.creado_en == ~U[2026-10-07 21:00:00.123456Z]
  end

  test "to_surreal/1 descarta record_id, campos virtuales y nils" do
    attrs =
      Ejemplo.to_surreal(%Ejemplo{id: "abc", record_id: "ejemplo:abc", nombre: "uno", nota: "x"})

    assert attrs == %{"id" => "abc", "nombre" => "uno"}
  end

  test "__surreal_fields__/0 no incluye campos virtuales" do
    assert Enum.map(Ejemplo.__surreal_fields__(), &elem(&1, 0)) == [
             :nombre,
             :cantidad,
             :creado_en
           ]
  end
end
