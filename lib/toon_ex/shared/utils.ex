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

      iex> ToonEx.Utils.list?([])
      true

      iex> ToonEx.Utils.list?([1, 2, 3])
      true

      iex> ToonEx.Utils.list?(%{})
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
    do_all_primitives?(list)
  end

  # Tail-recursive helper for performance
  defp do_all_primitives?([]), do: true

  defp do_all_primitives?([h | t])
       when is_nil(h) or is_boolean(h) or is_number(h) or is_binary(h),
       do: do_all_primitives?(t)

  defp do_all_primitives?(_), do: false

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
    do_all_maps?(list)
  end

  # Tail-recursive helper for performance
  defp do_all_maps?([]), do: true
  defp do_all_maps?([h | t]) when is_map(h), do: do_all_maps?(t)
  defp do_all_maps?(_), do: false

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
    do_same_keys?(rest, first_keys)
  end

  def same_keys?(_), do: false

  # Tail-recursive helper for performance
  defp do_same_keys?([], _first_keys), do: true

  defp do_same_keys?([map | rest], first_keys) when is_map(map) do
    if Map.keys(map) |> Enum.sort() == first_keys do
      do_same_keys?(rest, first_keys)
    else
      false
    end
  end

  defp do_same_keys?(_, _), do: false

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
    do_all_primitive_values?(list)
  end

  def all_primitive_values?(_), do: false

  # Tail-recursive helper for performance - single pass through all maps and values
  defp do_all_primitive_values?([]), do: true

  defp do_all_primitive_values?([map | rest]) when is_map(map) do
    if do_all_values_primitive?(map) do
      do_all_primitive_values?(rest)
    else
      false
    end
  end

  defp do_all_primitive_values?(_), do: false

  # Tail-recursive helper to check all values in a single map
  defp do_all_values_primitive?(map) when is_map(map) do
    do_all_values_primitive?(map, Map.keys(map))
  end

  defp do_all_values_primitive?(_map, []), do: true

  defp do_all_values_primitive?(map, [key | rest]) do
    case Map.get(map, key) do
      nil -> do_all_values_primitive?(map, rest)
      v when is_boolean(v) or is_number(v) or is_binary(v) -> do_all_values_primitive?(map, rest)
      _ -> false
    end
  end

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
      0

      iex> ToonEx.Utils.normalize(:infinity)
      nil
  """
  @spec normalize(term()) :: ToonEx.Types.encodable()
  # Performance: Inline hot function to reduce call overhead
  @compile {:inline, normalize: 1}

  # Fast-path for primitives - return immediately
  def normalize(nil), do: nil
  def normalize(value) when is_boolean(value), do: value
  def normalize(value) when is_binary(value), do: value

  # Atoms must be converted to strings
  def normalize(value) when is_atom(value), do: Atom.to_string(value)

  # Numbers: normalize zero and check finiteness per TOON spec Section 2
  def normalize(value) when is_number(value) do
    cond do
      value == 0 -> 0
      not is_finite(value) -> nil
      true -> value
    end
  end

  # Lists: tail-recursive normalization for performance
  def normalize(value) when is_list(value) do
    do_normalize_list(value, [])
  end

  # Structs - dispatch to ToonEx.Encoder protocol
  def normalize(%{__struct__: _} = struct) do
    result = ToonEx.Encoder.encode(struct, [])

    case result do
      binary when is_binary(binary) -> binary
      map when is_map(map) -> normalize(map)
      iodata -> IO.iodata_to_binary(iodata)
    end
  end

  # Maps: optimize key conversion and value normalization
  def normalize(value) when is_map(value) do
    do_normalize_map(value, %{})
  end

  # Fallback for unsupported types
  def normalize(_value), do: nil

  # Tail-recursive list normalization - avoids intermediate list allocations
  defp do_normalize_list([], acc), do: :lists.reverse(acc)
  defp do_normalize_list([h | t], acc), do: do_normalize_list(t, [normalize(h) | acc])

  # Map normalization with accumulator - avoids comprehension overhead
  defp do_normalize_map(map, acc) do
    :maps.fold(
      fn k, v, acc_map ->
        Map.put(acc_map, to_string(k), normalize(v))
      end,
      acc,
      map
    )
  end

  # Private helper to check if a number is finite
  @compile {:inline, is_finite: 1}
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
