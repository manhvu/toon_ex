defmodule ToonEx.Encode do
  @moduledoc """
  Main encoder for TOON format.

  This module coordinates the encoding process, dispatching to specialized
  encoders based on the type of value being encoded.
  """

  alias ToonEx.{EncodeError, Utils}
  alias ToonEx.Encode.{Objects, Options, Arrays, Primitives, Strings}

  # Performance: Direct binary constants to eliminate function call overhead
  @colon ":"
  @space " "
  @open_bracket "["
  @close_bracket "]"
  @list_item_marker "-"
  @list_item_prefix "- "

  @doc """
  Encodes Elixir data to TOON format string.

  ## Options

    * `:indent` - Number of spaces for indentation (default: 2)
    * `:delimiter` - Delimiter for array values: "," | "\\t" | "|" (default: ",")
    * `:length_marker` - Prefix for array length marker (default: nil)

  ## Examples

      iex> ToonEx.Encode.encode(%{"name" => "Alice", "age" => 30})
      {:ok, "age: 30\\nname: Alice"}

      iex> ToonEx.Encode.encode(%{"tags" => ["elixir", "toon"]})
      {:ok, "tags[2]: elixir,toon"}

      iex> ToonEx.Encode.encode(nil)
      {:ok, "null"}

      iex> ToonEx.Encode.encode(%{"name" => "Alice"}, indent: 4)
      {:ok, "name: Alice"}
  """
  @spec encode(ToonEx.Types.input(), keyword()) ::
          {:ok, String.t()} | {:error, EncodeError.t()}
  def encode(data, opts \\ []) do
    with {:ok, validated_opts} <- Options.validate(opts),
         {:ok, normalized} <- normalize(data) do
      try do
        encoded = do_encode(normalized, 0, validated_opts)
        {:ok, IO.iodata_to_binary(encoded)}
      rescue
        e in EncodeError -> {:error, e}
        e -> {:error, EncodeError.exception(message: Exception.message(e), value: data)}
      end
    else
      {:error, error} ->
        {:error,
         EncodeError.exception(
           message: "Invalid options: #{Exception.message(error)}",
           reason: error
         )}
    end
  end

  @spec encode_to_iodata!(ToonEx.Types.input(), keyword()) :: iodata()
  def encode_to_iodata!(data, opts \\ []) do
    with {:ok, validated_opts} <- Options.validate(opts),
         {:ok, normalized} <- normalize(data) do
      do_encode(normalized, 0, validated_opts)
    else
      {:error, error} ->
        raise EncodeError.exception(
                message: "Invalid options: #{Exception.message(error)}",
                reason: error
              )
    end
  end

  @doc """
  Encodes Elixir data to TOON format string, raising on error.

  ## Examples

      iex> ToonEx.Encode.encode!(%{"name" => "Alice"})
      "name: Alice"

      iex> ToonEx.Encode.encode!(%{"tags" => ["a", "b"]})
      "tags[2]: a,b"
  """
  @spec encode!(ToonEx.Types.input(), keyword()) :: String.t()
  def encode!(data, opts \\ []) do
    # Performance: Direct implementation - skip telemetry and error wrapping in hot path
    validated_opts = Options.validate!(opts)
    normalized = Utils.normalize(data)

    do_encode(normalized, 0, validated_opts)
    |> IO.iodata_to_binary()
  rescue
    e in EncodeError -> raise e
    e -> raise EncodeError.exception(message: Exception.message(e), value: data)
  end

  # Private functions

  @spec normalize(term()) :: {:ok, ToonEx.Types.encodable()} | {:error, EncodeError.t()}
  defp normalize(data) do
    {:ok, Utils.normalize(data)}
  rescue
    e ->
      {:error,
       EncodeError.exception(message: "Failed to normalize data: #{Exception.message(e)}")}
  end

  @spec do_encode(ToonEx.Types.encodable(), non_neg_integer(), map()) :: iodata()
  @doc false

  def do_encode(data, depth, opts) do
    cond do
      Utils.primitive?(data) ->
        Primitives.encode(data, opts.delimiter)

      is_list(data) and tuple_list?(data) ->
        map = Map.new(data)
        key_order = Enum.map(data, fn {k, _v} -> k end)
        # Return iodata directly - top-level encode/2 handles final binary conversion
        Objects.encode(map, depth, Map.put(opts, :key_order, key_order))

      Utils.map?(data) ->
        # Return iodata directly - top-level encode/2 handles final binary conversion
        Objects.encode(data, depth, opts)

      Utils.list?(data) ->
        encode_root_array(data, depth, opts)

      true ->
        raise EncodeError,
          message: "Cannot encode value of type #{inspect(data.__struct__ || :unknown)}",
          value: data
    end
  end

  # Check if a list is a tuple list (key-value pairs)
  defp tuple_list?([]), do: false
  defp tuple_list?([{k, _v} | _rest]) when is_binary(k), do: true
  defp tuple_list?(_), do: false

  # Encode root-level array per TOON spec Section 5
  # Performance: Single-pass array type detection instead of multiple Enum traversals
  defp encode_root_array([], _depth, opts) do
    length_marker = format_length_marker(0, opts.length_marker)
    ["[", length_marker, "]:"]
  end

  defp encode_root_array(data, depth, opts) do
    # Single-pass detection: determines array type while computing length
    case do_detect_array_type(data, {true, true, true, nil, 0}) do
      {:primitive, length} ->
        length_marker = format_length_marker(length, opts.length_marker)
        delimiter_marker = format_delimiter_marker(opts.delimiter)

        values =
          data
          |> Enum.map(&Primitives.encode(&1, opts.delimiter))
          |> Enum.intersperse(opts.delimiter)

        ["[", length_marker, delimiter_marker, "]: ", values]

      {:tabular, length, keys} ->
        length_marker = format_length_marker(length, opts.length_marker)
        delimiter_marker = format_delimiter_marker(opts.delimiter)
        encode_root_tabular_array(data, keys, length_marker, delimiter_marker, opts)

      {:list, length} ->
        length_marker = format_length_marker(length, opts.length_marker)
        delimiter_marker = format_delimiter_marker(opts.delimiter)
        encode_root_list_array(data, length_marker, delimiter_marker, depth, opts)
    end
  end

  # Single-pass array type detection
  # State: {all_primitives, all_maps, all_primitive_values, keys, count}
  # Tabular: all maps with same keys and all primitive values
  defp do_detect_array_type([], {false, true, true, keys, count})
       when is_list(keys) and keys != [],
       do: {:tabular, count, keys}

  # Primitive: all primitives (no maps)
  defp do_detect_array_type([], {true, _, _, _, count}),
    do: {:primitive, count}

  # List: everything else (mixed, non-uniform maps, or maps with non-primitive values)
  defp do_detect_array_type([], {_, _, _, _, count}),
    do: {:list, count}

  defp do_detect_array_type([h | t], {all_prim, all_maps, all_prim_vals, keys, count}) do
    new_count = count + 1

    cond do
      # Early exit: already determined as list (has both primitives and maps, or maps with non-primitive values)
      (not all_prim and not all_maps) or (all_maps and not all_prim_vals) ->
        do_count_remaining(t, new_count)

      # Primitive element - makes it not all-maps
      is_nil(h) or is_boolean(h) or is_number(h) or is_binary(h) ->
        do_detect_array_type(t, {all_prim, false, all_prim_vals, nil, new_count})

      # Map element
      is_map(h) ->
        h_keys = Map.keys(h) |> Enum.sort()
        h_all_prim = do_all_values_primitive?(h)

        new_keys =
          if keys do
            if h_keys == keys, do: keys, else: nil
          else
            h_keys
          end

        # If values aren't all primitive, we can early-exit to list
        if not h_all_prim do
          do_count_remaining(t, new_count)
        else
          do_detect_array_type(
            t,
            {false, all_maps, all_prim_vals and h_all_prim, new_keys, new_count}
          )
        end

      # Other element -> list
      true ->
        do_count_remaining(t, new_count)
    end
  end

  defp do_count_remaining([], count), do: {:list, count}
  defp do_count_remaining([_ | t], count), do: do_count_remaining(t, count + 1)

  defp do_all_values_primitive?(map) do
    :maps.fold(fn _k, v, acc -> acc and do_is_primitive?(v) end, true, map)
  end

  defp do_is_primitive?(v) when is_nil(v) or is_boolean(v) or is_number(v) or is_binary(v),
    do: true

  defp do_is_primitive?(_), do: false

  # Encode root tabular array - builds binary directly for memory efficiency
  # Encode root tabular array
  # Performance: Accepts pre-computed keys from single-pass detection
  defp encode_root_tabular_array(data, keys, length_marker, delimiter_marker, opts) do
    # Apply key_order if provided, otherwise use pre-computed sorted keys
    final_keys =
      case Map.get(opts, :key_order) do
        key_order when is_list(key_order) and key_order != [] ->
          ordered = Enum.filter(key_order, &(&1 in keys))
          if length(ordered) == length(keys), do: ordered, else: keys

        _ ->
          keys
      end

    # Build header as binary directly with braces around fields
    fields_bin = do_build_fields_binary(final_keys, opts.delimiter, <<>>)
    header_bin = "[#{length_marker}#{delimiter_marker}]#{fields_bin}:"

    # Build rows as binary directly - single pass with binary concatenation
    indent = opts.indent_string
    delim = opts.delimiter

    Enum.reduce(data, header_bin, fn obj, acc ->
      row_bin = do_build_row_binary(final_keys, obj, delim, <<>>)
      <<acc::binary, ?\n, indent::binary, row_bin::binary>>
    end)
  end

  # Performance: Tail-recursive binary field builder with braces
  defp do_build_fields_binary([], _delim, acc), do: <<"{", acc::binary, "}">>

  defp do_build_fields_binary([k], _delim, acc),
    do: <<"{", acc::binary, Strings.encode_key(k)::binary, "}">>

  defp do_build_fields_binary([k | rest], delim, acc),
    do:
      do_build_fields_binary(
        rest,
        delim,
        <<acc::binary, Strings.encode_key(k)::binary, delim::binary>>
      )

  # Performance: Tail-recursive binary row value builder
  defp do_build_row_binary([], _obj, _delim, acc), do: acc

  defp do_build_row_binary([k], obj, delim, acc),
    do: <<acc::binary, Primitives.encode(Map.get(obj, k), delim)::binary>>

  defp do_build_row_binary([k | rest], obj, delim, acc),
    do:
      do_build_row_binary(
        rest,
        obj,
        delim,
        <<acc::binary, Primitives.encode(Map.get(obj, k), delim)::binary, delim::binary>>
      )

  # Encode root list array - returns binary with newlines between items, no trailing newline per TOON spec Section 12
  defp encode_root_list_array(data, length_marker, delimiter_marker, _depth, opts) do
    header = [@open_bracket, length_marker, delimiter_marker, @close_bracket, @colon]

    items =
      Enum.flat_map(data, fn item ->
        encode_root_list_item(item, 0, opts)
      end)

    # Build iodata tree with newlines interspersed, then convert to binary
    [header | Enum.flat_map(items, fn item -> ["\n", [opts.indent_string, item]] end)]
    |> IO.iodata_to_binary()
  end

  # Encode a single root list item
  defp encode_root_list_item(item, _depth, _opts) when is_map(item) and map_size(item) == 0 do
    [[@list_item_marker, @space]]
  end

  defp encode_root_list_item(item, depth, opts) when is_map(item) do
    entries =
      item
      |> Enum.sort_by(fn {k, v} ->
        type_priority =
          cond do
            Utils.primitive?(v) -> 0
            is_list(v) -> 1
            is_map(v) -> 2
            true -> 3
          end

        {type_priority, k}
      end)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{k, v}, index} ->
        encode_root_list_entry(k, v, index, depth, opts)
      end)

    entries
  end

  defp encode_root_list_item(item, _depth, opts) when is_list(item) do
    # Array item - encode as inline array if all primitives
    cond do
      Enum.empty?(item) ->
        [[@list_item_prefix, "[0]:"]]

      Utils.all_primitives?(item) ->
        length_marker = format_length_marker(length(item), opts.length_marker)
        delimiter_marker = format_delimiter_marker(opts.delimiter)

        values =
          item
          |> Enum.map(&Primitives.encode(&1, opts.delimiter))
          |> Enum.intersperse(opts.delimiter)

        [
          [
            @list_item_prefix,
            @open_bracket,
            length_marker,
            delimiter_marker,
            @close_bracket,
            @colon,
            @space,
            values
          ]
        ]

      true ->
        # Complex nested array
        length_marker = format_length_marker(length(item), opts.length_marker)
        delimiter_marker = format_delimiter_marker(opts.delimiter)

        header = [
          @list_item_prefix,
          @open_bracket,
          length_marker,
          delimiter_marker,
          @close_bracket,
          @colon
        ]

        # Recursively encode nested items

        nested_items =
          Enum.flat_map(item, fn nested_item ->
            nested = encode_root_list_item(nested_item, 0, opts)

            Enum.map(nested, fn line ->
              [opts.indent_string | line]
            end)
          end)

        [header | nested_items]
    end
  end

  defp encode_root_list_item(item, _depth, opts) do
    # Primitive item
    [[@list_item_prefix, Primitives.encode(item, opts.delimiter)]]
  end

  # Encode a single entry in root list item
  defp encode_root_list_entry(k, v, index, depth, opts) do
    result =
      cond do
        Utils.primitive?(v) ->
          encoded_key = Strings.encode_key(k)
          needs_marker = index == 0

          line = [
            encoded_key,
            @colon,
            @space,
            Primitives.encode(v, opts.delimiter)
          ]

          if needs_marker do
            [[@list_item_prefix | line]]
          else
            [[opts.indent_string | line]]
          end

        v == %{} ->
          encoded_key = Strings.encode_key(k)
          needs_marker = index == 0

          line = [
            encoded_key,
            @colon,
            @space
          ]

          if needs_marker do
            [[@list_item_prefix | line]]
          else
            [[opts.indent_string | line]]
          end

        true ->
          encoded_key = Strings.encode_key(k)
          needs_marker = index == 0

          cond do
            is_map(v) ->
              # Header line: "- key:" or "  key:"
              header =
                if needs_marker,
                  do: [
                    @list_item_prefix,
                    encoded_key,
                    @colon
                  ],
                  else: [opts.indent_string, encoded_key, @colon]

              # Nested lines from Objects, each indented two extra levels (one for
              # the list item, one for the nested object depth).
              nested_lines =
                Objects.encode_to_lines(v, 0, opts)
                |> Enum.map(&[opts.indent_string, opts.indent_string, &1])

              [header | nested_lines]

            is_list(v) ->
              # ← encode, not encode_list
              [header | data_lines] = Arrays.encode(k, v, depth + 1, opts)

              marked_header =
                if needs_marker,
                  do: [@list_item_prefix, header],
                  else: [opts.indent_string, header]

              # Both tabular and list arrays need 2 indents when nested inside a list item's map entry
              indented_data =
                Enum.map(data_lines, &[opts.indent_string, opts.indent_string, &1])

              [marked_header | indented_data]

            true ->
              raise ToonEx.EncodeError,
                message: "Cannot encode value in list entry: #{inspect(v)}",
                value: v
          end
      end

    result
  end

  # Format length marker
  defp format_length_marker(length, nil), do: Integer.to_string(length)
  defp format_length_marker(length, marker), do: marker <> Integer.to_string(length)

  @compile {:inline, format_delimiter_marker: 1}
  defp format_delimiter_marker(","), do: ""
  defp format_delimiter_marker(delimiter), do: delimiter
end
