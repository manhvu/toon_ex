defmodule ToonEx.Utils do
  @moduledoc false

  @spec primitive?(term()) :: boolean()
  def primitive?(nil), do: true
  def primitive?(value) when is_boolean(value), do: true
  def primitive?(value) when is_number(value), do: true
  def primitive?(value) when is_binary(value), do: true
  def primitive?(_), do: false

  @doc """
  Checks if a value is a map (object).

  ## Examples

      iex> ToonEx.Utils.map?(%{})
      true

      iex> ToonEx.Utils.map?(%{"key" => "value"})
      true

      iex> ToonEx.Utils.map?([])
      false
  """
  @spec map?(term()) :: boolean()
  def map?(value) when is_map(value), do: true
  def map?(_), do: false

  @doc """
  Checks if a value is a list (array).

  ## Examples

      iex> Toon.Utils.list?([])
      true

      iex> Toon.Utils.list?([1, 2, 3])
      true

      iex> Toon.Utils.list?(%{})
      false
  """
  @spec list?(term()) :: boolean()
  def list?(value) when is_list(value), do: true
  def list?(_), do: false

  @doc """
  Checks if all elements in a list are primitives.

  ## Examples

      iex> ToonEx.Utils.all_primitives?([1, 2, 3])
      true

      iex> ToonEx.Utils.all_primitives?(["a", "b", "c"])
      true

      iex> ToonEx.Utils.all_primitives?([1, %{}, 3])
      false

      iex> ToonEx.Utils.all_primitives?([])
      true
  """
  @spec all_primitives?(list()) :: boolean()
  def all_primitives?(list) when is_list(list) do
    Enum.all?(list, &primitive?/1)
  end

  @doc """
  Checks if all elements in a list are maps.

  ## Examples

      iex> ToonEx.Utils.all_maps?([%{}, %{}])
      true

      iex> ToonEx.Utils.all_maps?([%{"a" => 1}, %{"b" => 2}])
      true

      iex> ToonEx.Utils.all_maps?([%{}, 1])
      false

      iex> ToonEx.Utils.all_maps?([])
      true
  """
  @spec all_maps?(list()) :: boolean()
  def all_maps?(list) when is_list(list) do
    Enum.all?(list, &map?/1)
  end

  @doc """
  Checks if all maps in a list have the same keys (for tabular format detection).

  ## Examples

      iex> ToonEx.Utils.same_keys?([%{"a" => 1}, %{"a" => 2}])
      true

      iex> ToonEx.Utils.same_keys?([%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}])
      true

      iex> ToonEx.Utils.same_keys?([%{"a" => 1}, %{"b" => 2}])
      false

      iex> ToonEx.Utils.same_keys?([%{}, %{}])
      false

      iex> ToonEx.Utils.same_keys?([])
      true
  """
  @spec same_keys?(list()) :: boolean()
  def same_keys?([]), do: true

  # don't treat empty maps has same keys
  def same_keys?([first | rest]) when is_map(first) and map_size(first) > 0 do
    first_keys = Map.keys(first) |> Enum.sort()

    Enum.all?(rest, fn map ->
      is_map(map) and Map.keys(map) |> Enum.sort() == first_keys
    end)
  end

  def same_keys?(_), do: false

  @doc """
  Checks if all values in all maps of a list are primitives (for tabular format).

  ## Examples

      iex> ToonEx.Utils.all_primitive_values?([%{"a" => 1}, %{"a" => 2}])
      true

      iex> ToonEx.Utils.all_primitive_values?([%{"a" => 1, "b" => "x"}, %{"a" => 2, "b" => "y"}])
      true

      iex> ToonEx.Utils.all_primitive_values?([%{"a" => %{"nested" => 1}}])
      false

      iex> ToonEx.Utils.all_primitive_values?([%{"a" => [1, 2]}])
      false

      iex> ToonEx.Utils.all_primitive_values?([])
      true
  """
  @spec all_primitive_values?(list()) :: boolean()

  def all_primitive_values?([]), do: true

  def all_primitive_values?(list) when is_list(list) do
    Enum.all?(list, fn map ->
      is_map(map) and Enum.all?(map, fn {_k, v} -> primitive?(v) end)
    end)
  end

  def all_primitive_values?(_), do: false

  @doc """
  Repeats a string n times.

  ## Examples

      iex> ToonEx.Utils.repeat("  ", 0)
      ""

      iex> ToonEx.Utils.repeat("  ", 1)
      "  "

      iex> ToonEx.Utils.repeat("  ", 3)
      "      "
  """
  @spec repeat(String.t(), non_neg_integer()) :: String.t()
  def repeat(_string, 0), do: ""

  def repeat(string, times) when times > 0 do
    String.duplicate(string, times)
  end

  @doc """
  Normalizes a value for encoding, converting non-standard types to JSON-compatible ones.

  ## Examples

      iex> ToonEx.Utils.normalize(42)
      42

      iex> ToonEx.Utils.normalize(-0.0)
      -0.0

      iex> ToonEx.Utils.normalize(:infinity)
      nil
  """
  @spec normalize(term()) :: ToonEx.Types.encodable()
  def normalize(nil), do: nil
  def normalize(value) when is_boolean(value), do: value
  def normalize(value) when is_binary(value), do: value
  def normalize(value) when is_atom(value), do: Atom.to_string(value)

  def normalize(value) when is_number(value) do
    cond do
      # Any zero (positive or negative) → integer 0 per TOON spec.
      # The previous atan2 trick was inverted: atan2(+0.0,-1)=+π, atan2(-0.0,-1)=-π,
      # so the old guard was matching +0.0 and letting -0.0 fall through unchanged.
      value == 0 -> 0
      not is_finite(value) -> nil
      true -> value
    end
  end

  def normalize(value) when is_list(value) do
    Enum.map(value, &normalize/1)
  end

  # Structs - dispatch to Toon.Encoder protocol
  def normalize(%{__struct__: _} = struct) do
    result = ToonEx.Encoder.encode(struct, [])

    # If encoder returns iodata (string), convert it to binary
    # If encoder returns a map (from @derive), normalize it recursively
    case result do
      binary when is_binary(binary) -> binary
      map when is_map(map) -> normalize(map)
      iodata -> IO.iodata_to_binary(iodata)
    end
  end

  def normalize(value) when is_map(value) do
    for {k, v} <- value, into: %{}, do: {to_string(k), normalize(v)}
  end

  # Fallback for unsupported types
  def normalize(_value), do: nil

  # Private helper to check if a number is finite
  defp is_finite(value) when is_float(value) do
    # NaN check: NaN != NaN is the standard IEEE 754 way to detect NaN
    # credo:disable-for-lines:2
    is_nan = value != value
    # Infinity check: infinity is beyond maximum representable float
    is_inf = abs(value) > 1.0e308

    not is_nan and not is_inf
  end

  defp is_finite(value) when is_integer(value), do: true
end
