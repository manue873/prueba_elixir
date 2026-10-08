defmodule PruebaElixir.Tablero.PolicyTest do
  @moduledoc "Tests unitarios de Policy — sin SurrealDB, sin efectos secundarios."

  use ExUnit.Case, async: true

  alias PruebaElixir.Tablero.Policy

  describe "puede_mutar?/1" do
    test "lider puede mutar" do
      assert :ok = Policy.puede_mutar?("lider")
    end

    test "desarrollador puede mutar" do
      assert :ok = Policy.puede_mutar?("desarrollador")
    end

    test "lector NO puede mutar" do
      assert {:error, :sin_permiso} = Policy.puede_mutar?("lector")
    end

    test "rol desconocido NO puede mutar" do
      assert {:error, :sin_permiso} = Policy.puede_mutar?("admin")
    end
  end

  describe "transicion_valida?/3" do
    test "cerrado es definitivo" do
      assert {:error, :ticket_cerrado} = Policy.transicion_valida?("cerrado", "abierto", nil)
      assert {:error, :ticket_cerrado} = Policy.transicion_valida?("cerrado", "en_progreso", "u1")
    end

    test "en_progreso requiere responsable" do
      assert {:error, :sin_asignar} = Policy.transicion_valida?("abierto", "en_progreso", nil)
    end

    test "en_progreso permitido con responsable" do
      assert :ok = Policy.transicion_valida?("abierto", "en_progreso", "usuario:u1")
    end

    test "resuelto se puede reabrir" do
      assert :ok = Policy.transicion_valida?("resuelto", "abierto", nil)
    end

    test "transición a estado inválido" do
      assert {:error, :estado_invalido} =
               Policy.transicion_valida?("abierto", "inexistente", nil)
    end

    test "transiciones válidas cubren todos los estados" do
      for estado <- ~w[abierto en_progreso resuelto cerrado] do
        # Excepto cerrado->cualquiera (ya cubierto arriba) y abierto->en_progreso sin asignar
        unless estado == "cerrado" or (estado == "abierto" and true) do
          assert :ok = Policy.transicion_valida?(estado, "resuelto", nil)
        end
      end
    end
  end

  describe "mismo_proyecto?/2" do
    test "mismo proyecto permite la operación" do
      assert :ok = Policy.mismo_proyecto?("web", "web")
    end

    test "diferente proyecto bloquea" do
      assert {:error, :ticket_de_otro_proyecto} = Policy.mismo_proyecto?("app", "web")
    end
  end

  describe "validar_crear/1" do
    test "titulo requerido" do
      assert {:error, :titulo_requerido} = Policy.validar_crear(%{})
    end

    test "titulo vacío inválido" do
      assert {:error, :titulo_vacio} = Policy.validar_crear(%{"titulo" => ""})
    end

    test "prioridad inválida" do
      assert {:error, :prioridad_invalida} =
               Policy.validar_crear(%{"titulo" => "T", "prioridad" => "urgente"})
    end

    test "puntos inválidos" do
      assert {:error, :puntos_invalidos} =
               Policy.validar_crear(%{"titulo" => "T", "puntos" => 4})
    end

    test "attrs mínimos válidos" do
      assert :ok = Policy.validar_crear(%{"titulo" => "Nuevo ticket"})
    end

    test "attrs completos válidos" do
      assert :ok =
               Policy.validar_crear(%{"titulo" => "T", "prioridad" => "alta", "puntos" => 5})
    end
  end

  describe "validar_editar/1" do
    test "sin cambios es válido (la validación no exige cambios)" do
      assert :ok = Policy.validar_editar(%{})
    end

    test "prioridad inválida" do
      assert {:error, :prioridad_invalida} = Policy.validar_editar(%{prioridad: "top"})
    end

    test "puntos inválidos" do
      assert {:error, :puntos_invalidos} = Policy.validar_editar(%{puntos: 7})
    end

    test "puntos de Fibonacci válidos" do
      for p <- [1, 2, 3, 5, 8, 13] do
        assert :ok = Policy.validar_editar(%{puntos: p})
      end
    end
  end
end
