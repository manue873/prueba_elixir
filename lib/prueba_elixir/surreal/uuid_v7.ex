defmodule PruebaElixir.Surreal.UUIDv7 do
  @moduledoc """
  Generador UUIDv7 sin dependencias: `Repo.insert/3` lo usa como id cuando el
  registro no trae uno. Al empezar por el timestamp, los ids salen ordenados en
  el tiempo.
  """

  import Bitwise

  defmodule Type do
    @moduledoc """
    Marca de tipo para `field/3`: un campo declarado con este tipo se envía a
    SurrealDB como `<uuid>` en vez de como string.
    """
  end

  @uuid_v7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  @spec generate() :: String.t()
  def generate do
    timestamp = System.system_time(:millisecond) &&& (1 <<< 48) - 1
    random = :crypto.strong_rand_bytes(10) |> :binary.decode_unsigned()
    random_a = random >>> 68
    random_b = random &&& (1 <<< 62) - 1

    value =
      timestamp <<< 80 |||
        7 <<< 76 |||
        random_a <<< 64 |||
        2 <<< 62 |||
        random_b

    value
    |> then(&:binary.encode_unsigned(&1, :big))
    |> Base.encode16(case: :lower)
    |> format()
  end

  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value), do: Regex.match?(@uuid_v7_regex, value)
  def valid?(_value), do: false

  defp format(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
           e::binary-size(12)>>
       ) do
    Enum.join([a, b, c, d, e], "-")
  end
end
