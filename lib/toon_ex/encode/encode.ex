defmodule ToonEx.Encode do
  @moduledoc """
  Main encoder for TOON format.

  This module coordinates the encoding process, dispatching to specialized
  encoders based on the type of value being encoded.
  """

  alias ToonEx.{Constants, EncodeError, Utils}
  alias ToonEx.Encode.{Objects, Options, Arrays, Primitives, Strings}

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
    start_time = System.monotonic_time()
    metadata = %{data_type: data_type(data)}

    :telemetry.execute(
      [:toon_ex, :encode, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
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

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, encoded} ->
        :telemetry.execute(
          [:toon_ex, :encode, :stop],
          %{duration: duration, size: byte_size(encoded)},
          metadata
        )

      {:error, error} ->
        :telemetry.execute(
          [:toon_ex, :encode, :exception],
          %{duration: duration},
          Map.put(metadata, :error, error)
        )
    end

    result
  end

  @spec encode_to_iodata!(ToonEx.Types.input(), keyword()) :: iodata()
  def encode_to_iodata!(data, opts \\ []) do
    start_time = System.monotonic_time()
    metadata = %{data_type: data_type(data)}

    :telemetry.execute(
      [:toon_ex, :encode_to_iodata, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
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

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:toon_ex, :encode_to_iodata, :stop],
      %{duration: duration},
      metadata
    )

    result
  end

  defp data_type(data) when is_map(data), do: :map
  defp data_type(data) when is_list(data), do: :list
  defp data_type(nil), do: :null
  defp data_type(data) when is_boolean(data), do: :boolean
  defp data_type(data) when is_number(data), do: :number
  defp data_type(data) when is_binary(data), do: :string
  defp data_type(_), do: :unknown

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
    case encode(data, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
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

        Objects.encode(map, depth, Map.put(opts, :key_order, key_order))
        |> IO.iodata_to_binary()

      Utils.map?(data) ->
        Objects.encode(data, depth, opts)
        |> IO.iodata_to_binary()

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
  defp encode_root_array(data, depth, opts) do
    length_marker = format_length_marker(length(data), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    cond do
      # Empty array
      Enum.empty?(data) ->
        length_marker = format_length_marker(0, opts.length_marker)
        ["[", length_marker, "]:"]

      # Inline array (all primitives)
      Utils.all_primitives?(data) ->
        values =
          data
          |> Enum.map(&Primitives.encode(&1, opts.delimiter))
          |> Enum.intersperse(opts.delimiter)

        ["[", length_marker, delimiter_marker, "]: ", values]

      # Tabular array (all maps with same keys and primitive values only)
      Utils.all_maps?(data) and Utils.same_keys?(data) and Utils.all_primitive_values?(data) ->
        encode_root_tabular_array(data, length_marker, delimiter_marker, opts)

      # List format (mixed or non-uniform)
      true ->
        encode_root_list_array(data, length_marker, delimiter_marker, depth, opts)
    end
  end

  # Encode root tabular array
  #
  defp encode_root_tabular_array(data, length_marker, delimiter_marker, opts) do
    keys =
      case data do
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

    # Field names in {…} are ALWAYS comma-separated regardless of row delimiter.
    fields = keys |> Enum.map(&Strings.encode_key/1) |> Enum.intersperse(",")

    header = [
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
      Enum.map(data, fn obj ->
        values =
          keys
          |> Enum.map(&Map.get(obj, &1))
          |> Enum.map(&Primitives.encode(&1, opts.delimiter))
          # row data still uses opts.delimiter
          |> Enum.intersperse(opts.delimiter)

        [opts.indent_string, values]
      end)

    [header | rows]
    |> Enum.map_join("\n", &IO.iodata_to_binary/1)
  end

  # Encode root list array
  defp encode_root_list_array(data, length_marker, delimiter_marker, depth, opts) do
    header = ["[", length_marker, delimiter_marker, "]:"]

    items =
      Enum.flat_map(data, fn item ->
        encode_root_list_item(item, depth, opts)
      end)

    result =
      [
        IO.iodata_to_binary(header)
        | Enum.map(items, fn line -> [opts.indent_string, line] end)
      ]
      |> Enum.map_join("\n", &IO.iodata_to_binary/1)

    # <── trailing newline to match TOON document convention
    result <> "\n"
  end

  # Encode a single root list item
  defp encode_root_list_item(item, _depth, _opts) when is_map(item) and map_size(item) == 0 do
    [[Constants.list_item_marker(), Constants.space()]]
  end

  defp encode_root_list_item(item, depth, opts) when is_map(item) do
    entries =
      item
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
        [[Constants.list_item_marker(), Constants.space(), "[0]:"]]

      Utils.all_primitives?(item) ->
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

      true ->
        # Complex nested array
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
    [[Constants.list_item_marker(), Constants.space(), Primitives.encode(item, opts.delimiter)]]
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
            Constants.colon(),
            Constants.space(),
            Primitives.encode(v, opts.delimiter)
          ]

          if needs_marker do
            [[Constants.list_item_marker(), Constants.space() | line]]
          else
            [[opts.indent_string | line]]
          end

        v == %{} ->
          encoded_key = Strings.encode_key(k)
          needs_marker = index == 0

          line = [
            encoded_key,
            Constants.colon(),
            Constants.space()
          ]

          if needs_marker do
            [[Constants.list_item_marker(), Constants.space() | line]]
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
                    Constants.list_item_marker(),
                    Constants.space(),
                    encoded_key,
                    Constants.colon()
                  ],
                  else: [opts.indent_string, encoded_key, Constants.colon()]

              # Nested lines from Objects, each indented two extra levels (one for
              # the list item, one for the nested object depth).
              nested_lines =
                Objects.encode_to_lines(v, 0, opts)
                |> Enum.map(&[opts.indent_string, opts.indent_string, &1])

              [header | nested_lines]

            is_list(v) ->
              [header | data_lines] = Arrays.encode_list(k, v, depth + 1, opts)

              marked_header =
                if needs_marker,
                  do: [Constants.list_item_marker(), Constants.space(), header],
                  else: [opts.indent_string, header]

              # ONE opts.indent_string, not two
              indented_data = Enum.map(data_lines, &[opts.indent_string, &1])
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
