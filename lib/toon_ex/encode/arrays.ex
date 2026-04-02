defmodule ToonEx.Encode.Arrays do
  @moduledoc """
  Encoding of TOON arrays in three formats:
  - Inline: for primitive arrays (e.g., tags[2]: reading,gaming)
  - Tabular: for uniform object arrays (e.g., users[2]{name,age}: Alice,30 / Bob,25)
  - List: for mixed or non-uniform arrays
  """

  alias ToonEx.Constants
  alias ToonEx.Encode.{Primitives, Strings, Objects}
  alias ToonEx.Utils

  @doc """
  Encodes an array with the given key.

  Automatically detects the appropriate format based on array contents.
  """
  @spec encode(String.t(), list(), non_neg_integer(), map()) :: [iodata()]
  def encode(key, list, depth, opts) when is_list(list) do
    cond do
      Enum.empty?(list) ->
        encode_empty(key, opts.length_marker)

      Utils.all_primitives?(list) ->
        encode_inline(key, list, opts)

      Utils.all_maps?(list) and Utils.same_keys?(list) and can_be_tabular?(list) ->
        encode_tabular(key, list, depth, opts)

      true ->
        encode_list(key, list, depth, opts)
    end
  end

  # Check if array of objects can be encoded in tabular format
  # Tabular format requires all values to be primitives
  defp can_be_tabular?(list) do
    Enum.all?(list, fn obj ->
      Enum.all?(obj, fn {_k, v} -> Utils.primitive?(v) end)
    end)
  end

  @doc """
  Encodes an empty array.

  ## Examples

      iex> result = ToonEx.Encode.Arrays.encode_empty("items", nil)
      iex> IO.iodata_to_binary(result)
      "items[0]:"
  """
  @spec encode_empty(String.t(), String.t() | nil) ::
          nonempty_list(nonempty_list(binary() | nonempty_list(binary())))
  def encode_empty(key, length_marker \\ nil) do
    marker = format_length_marker(0, length_marker)
    [[Strings.encode_key(key), "[", marker, "]", Constants.colon()]]
  end

  @doc """
  Encodes a primitive array in inline format.

  ## Examples

      iex> opts = %{delimiter: ",", length_marker: nil}
      iex> result = ToonEx.Encode.Arrays.encode_inline("tags", ["reading", "gaming"], opts)
      iex> IO.iodata_to_binary(result)
      "tags[2]: reading,gaming"
  """
  @spec encode_inline(String.t(), list(), map()) :: [iodata()]
  def encode_inline(key, list, opts) do
    length_marker = format_length_marker(length(list), opts.length_marker)
    encoded_key = Strings.encode_key(key)

    values =
      list
      |> Enum.map(&Primitives.encode(&1, opts.delimiter))
      |> Enum.intersperse(opts.delimiter)

    # Include delimiter marker in header per TOON spec Section 6
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [
      encoded_key,
      "[",
      length_marker,
      delimiter_marker,
      "]",
      Constants.colon(),
      Constants.space()
    ]

    [[header, values]]
  end

  @doc """
  Encodes a uniform object array in tabular format.

  Returns a list where the first element is the header, and subsequent elements
  are data rows (without indentation - indentation is added by the Writer).

  ## Examples

      iex> opts = %{delimiter: ",", length_marker: nil, indent_string: "  "}
      iex> users = [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
      iex> [header | rows] = ToonEx.Encode.Arrays.encode_tabular("users", users, 0, opts)
      iex> IO.iodata_to_binary(header)
      "users[2]{age,name}:"
      iex> Enum.map(rows, &IO.iodata_to_binary/1)
      ["30,Alice", "25,Bob"]
  """
  @spec encode_tabular(String.t(), list(), non_neg_integer(), map()) :: [iodata()]
  def encode_tabular(key, list, _depth, opts) do
    length_marker = format_length_marker(length(list), opts.length_marker)
    encoded_key = Strings.encode_key(key)

    keys =
      case list do
        [first | _] ->
          map_keys = Map.keys(first)
          key_order = Map.get(opts, :key_order)

          if is_list(key_order) and not Enum.empty?(key_order) do
            ordered = Enum.filter(key_order, &(&1 in map_keys))
            if length(ordered) == length(map_keys), do: ordered, else: Enum.sort(map_keys)
          else
            Enum.sort(map_keys)
          end

        [] ->
          []
      end

    # Field names in {…} use the active delimiter per TOON spec Section 6.
    fields = keys |> Enum.map(&Strings.encode_key/1) |> Enum.intersperse(opts.delimiter)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [
      encoded_key,
      "[",
      length_marker,
      delimiter_marker,
      "]",
      Constants.open_brace(),
      fields,
      Constants.close_brace(),
      Constants.colon()
    ]

    rows =
      Enum.map(list, fn obj ->
        keys
        |> Enum.map(&Map.get(obj, &1))
        |> Enum.map(&Primitives.encode(&1, opts.delimiter))
        # row data still uses opts.delimiter
        |> Enum.intersperse(opts.delimiter)
      end)

    [header | rows]
  end

  @doc """
  Encodes an array in list format (for mixed or non-uniform arrays).

  Returns a list where the first element is the header, and subsequent elements
  are list items (without base indentation - indentation is added by the Writer).

  ## Examples

      iex> opts = %{delimiter: ",", length_marker: nil, indent_string: "  "}
      iex> items = [%{"title" => "Book", "price" => 9}, %{"title" => "Movie", "duration" => 120}]
      iex> [header | list_items] = ToonEx.Encode.Arrays.encode_list("items", items, 0, opts)
      iex> IO.iodata_to_binary(header)
      "items[2]:"
      iex> Enum.map(list_items, &IO.iodata_to_binary/1)
      ["- price: 9", "  title: Book", "- duration: 120", "  title: Movie"]
  """
  @spec encode_list(String.t(), list(), non_neg_integer(), map()) :: [iodata()]
  def encode_list(key, list, depth, opts) do
    length_marker = format_length_marker(length(list), opts.length_marker)
    encoded_key = Strings.encode_key(key)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [encoded_key, "[", length_marker, delimiter_marker, "]", Constants.colon()]

    items =
      Enum.flat_map(list, fn item ->
        encode_list_item(item, depth, opts)
      end)

    [header | items]
  end

  # Private helpers

  defp format_length_marker(length, nil), do: Integer.to_string(length)
  defp format_length_marker(length, marker), do: marker <> Integer.to_string(length)

  @compile {:inline, format_delimiter_marker: 1}
  defp format_delimiter_marker(","), do: ""
  defp format_delimiter_marker(delimiter), do: delimiter

  # Pattern match on empty map first
  defp encode_list_item(item, _depth, _opts) when item == %{} do
    # Empty object encodes as bare hyphen
    [[Constants.list_item_marker()]]
  end

  # Map items in list
  defp encode_list_item(item, depth, opts) when is_map(item) do
    keys = get_ordered_map_keys(item, Map.get(opts, :key_order))

    keys
    |> Enum.with_index()
    |> Enum.flat_map(fn {k, index} ->
      v = Map.get(item, k)
      encode_map_entry_with_marker(k, v, index, depth, opts)
    end)
  end

  # Array items in list - delegate to specific handlers
  defp encode_list_item(item, _depth, opts) when is_list(item) and item == [] do
    encode_empty_array_item(opts)
  end

  defp encode_list_item(item, _depth, opts) when is_list(item) do
    if Utils.all_primitives?(item) do
      encode_inline_array_item(item, opts)
    else
      encode_complex_array_item(item, opts)
    end
  end

  # Primitive items in list
  defp encode_list_item(item, _depth, opts) do
    encode_primitive_item(item, opts)
  end

  # Extract helpers for array item types
  defp encode_empty_array_item(opts) do
    length_marker = format_length_marker(0, opts.length_marker)
    [[Constants.list_item_marker(), Constants.space(), "[", length_marker, "]:"]]
  end

  defp encode_inline_array_item(item, opts) do
    length_marker = format_length_marker(length(item), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    values =
      item
      |> Enum.map(&Primitives.encode(&1, opts.delimiter))
      |> Enum.intersperse(opts.delimiter)

    [
      [
        Constants.list_item_marker(),
        Constants.space(),
        "[",
        length_marker,
        delimiter_marker,
        "]",
        Constants.colon(),
        Constants.space(),
        values
      ]
    ]
  end

  defp encode_complex_array_item(item, opts) do
    length_marker = format_length_marker(length(item), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [
      Constants.list_item_marker(),
      Constants.space(),
      "[",
      length_marker,
      delimiter_marker,
      "]",
      Constants.colon()
    ]

    nested_items =
      Enum.flat_map(item, fn nested_item ->
        nested = encode_list_item(nested_item, 0, opts)
        Enum.map(nested, fn line -> [opts.indent_string | line] end)
      end)

    [header | nested_items]
  end

  defp encode_primitive_item(item, opts) do
    [
      [
        Constants.list_item_marker(),
        Constants.space(),
        Primitives.encode(item, opts.delimiter)
      ]
    ]
  end

  # Helper to get ordered keys for map items
  defp get_ordered_map_keys(item, key_order) do
    map_keys = Map.keys(item)

    if is_list(key_order) and not Enum.empty?(key_order) do
      ordered_keys = Enum.filter(key_order, &(&1 in map_keys))
      extra_keys = Enum.filter(map_keys, &(&1 not in key_order)) |> Enum.sort()
      ordered_keys ++ extra_keys
    else
      Enum.sort(map_keys)
    end
  end

  # Helper for encoding map entries with list markers
  defp encode_map_entry_with_marker(k, v, index, depth, opts) do
    encoded_key = Strings.encode_key(k)
    needs_marker = index == 0

    encode_value_with_optional_marker(encoded_key, v, needs_marker, depth, opts)
  end

  # Encode primitive values
  defp encode_value_with_optional_marker(key, v, needs_marker, _depth, opts)
       when is_nil(v) or is_boolean(v) or is_number(v) or is_binary(v) do
    line = build_primitive_line(key, v, opts)
    [apply_marker(line, needs_marker, opts)]
  end

  # Encode empty array
  defp encode_value_with_optional_marker(key, [], needs_marker, _depth, opts) do
    line = build_empty_array_line(key, opts)
    [apply_marker(line, needs_marker, opts)]
  end

  # Encode inline primitive array
  defp encode_value_with_optional_marker(key, v, needs_marker, _depth, opts)
       when is_list(v) do
    if Utils.all_primitives?(v) do
      line = build_inline_array_line(key, v, opts)
      [apply_marker(line, needs_marker, opts)]
    else
      encode_complex_array_value(key, v, needs_marker, opts)
    end
  end

  # Encode map values
  defp encode_value_with_optional_marker(key, v, needs_marker, depth, opts) when is_map(v) do
    header_line = [key, Constants.colon()]
    nested_result = encode_nested_map(v, depth, opts)

    if needs_marker do
      [[Constants.list_item_marker(), Constants.space(), header_line] | nested_result]
    else
      [[opts.indent_string, header_line] | nested_result]
    end
  end

  # Fallback for unsupported types
  defp encode_value_with_optional_marker(key, _v, needs_marker, _depth, opts) do
    line = [key, Constants.colon(), Constants.space(), Constants.null_literal()]
    [apply_marker(line, needs_marker, opts)]
  end

  # Helpers for building lines
  defp build_primitive_line(key, value, opts) do
    [key, Constants.colon(), Constants.space(), Primitives.encode(value, opts.delimiter)]
  end

  defp build_empty_array_line(key, opts) do
    length_marker = format_length_marker(0, opts.length_marker)
    [Strings.encode_key(key), "[", length_marker, "]", Constants.colon()]
  end

  defp build_inline_array_line(key, values, opts) do
    length_marker = format_length_marker(length(values), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    encoded_values =
      values
      |> Enum.map(&Primitives.encode(&1, opts.delimiter))
      |> Enum.intersperse(opts.delimiter)

    [
      Strings.encode_key(key),
      "[",
      length_marker,
      delimiter_marker,
      "]",
      Constants.colon(),
      Constants.space(),
      encoded_values
    ]
  end

  # Apply list marker or indent based on needs_marker flag
  defp apply_marker(line, true, _opts) do
    [Constants.list_item_marker(), Constants.space() | line]
  end

  defp apply_marker(line, false, opts) do
    [opts.indent_string | line]
  end

  # Handle complex arrays (tabular, list, or nested)
  defp encode_complex_array_value(key, v, needs_marker, opts) do
    depth = 0

    cond do
      tabular_array?(v) ->
        encode_tabular_array_value(key, v, needs_marker, depth, opts)

      list_array?(v) ->
        encode_list_array_value(key, v, needs_marker, depth, opts)

      true ->
        encode_other_array_value(key, v, needs_marker, depth, opts)
    end
  end

  defp tabular_array?(v) do
    Utils.all_maps?(v) and Utils.same_keys?(v) and
      Enum.all?(v, fn obj -> Enum.all?(obj, fn {_k, val} -> Utils.primitive?(val) end) end)
  end

  defp list_array?(v) do
    Utils.all_maps?(v) and
      (not Utils.same_keys?(v) or
         Enum.any?(v, fn obj ->
           Enum.any?(obj, fn {_k, val} -> not Utils.primitive?(val) end)
         end))
  end

  defp encode_tabular_array_value(key, v, needs_marker, depth, opts) do
    [header | data_rows] = encode(key, v, depth + 1, opts)
    header_line = apply_marker(header, needs_marker, opts)
    data_lines = Enum.map(data_rows, fn row -> [opts.indent_string, opts.indent_string, row] end)
    [header_line | data_lines]
  end

  defp encode_list_array_value(key, v, needs_marker, depth, opts) do
    [header | list_items] = encode(key, v, depth + 1, opts)
    header_line = apply_marker(header, needs_marker, opts)

    item_lines =
      Enum.map(list_items, fn line -> [opts.indent_string, opts.indent_string, line] end)

    [header_line | item_lines]
  end

  defp encode_other_array_value(key, v, needs_marker, depth, opts) do
    nested = encode(key, v, depth + 1, opts)

    if needs_marker do
      [first_line | rest] = nested

      [
        [Constants.list_item_marker(), Constants.space(), first_line]
        | Enum.map(rest, fn line -> [opts.indent_string, line] end)
      ]
    else
      Enum.map(nested, fn line -> [opts.indent_string, line] end)
    end
  end

  defp encode_nested_map(v, depth, opts) do
    Objects.encode_to_lines(v, depth + 1, opts)
    |> Enum.map(&[opts.indent_string, &1])
  end
end
