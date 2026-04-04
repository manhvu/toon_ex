defmodule ToonEx.Encode.Objects do
  @moduledoc """
  Encoding of TOON objects (maps).
  """

  alias ToonEx.Constants
  alias ToonEx.Encode.{Arrays, Primitives, Strings, Writer}
  alias ToonEx.Utils

  @identifier_segment_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @doc """
  Encodes a map to TOON format.

  ## Examples

      iex> opts = %{indent: 2, delimiter: ",", length_marker: nil}
      iex> map = %{"name" => "Alice", "age" => 30}
      iex> ToonEx.Encode.Objects.encode(map, 0, opts)

  """
  @spec encode(map(), non_neg_integer(), map()) :: [iodata()]
  def encode(map, depth, opts) when is_map(map) do
    map
    |> do_encode_map(depth, opts)
    |> Writer.to_iodata()
  end

  def encode_to_lines(map, depth, opts) do
    map
    |> do_encode_map(depth, opts)
    |> Writer.to_lines()
  end

  # All the real work lives here; both encode/3 and encode_to_lines/3 delegate.
  defp do_encode_map(map, depth, opts) do
    writer = Writer.new(opts.indent)
    keys = get_ordered_keys(map, Map.get(opts, :key_order), [])

    opts =
      if depth == 0 and not Map.has_key?(opts, :forbidden_fold_paths) do
        Map.put(opts, :forbidden_fold_paths, collect_forbidden_fold_paths(keys))
      else
        opts
      end

    path_prefix = Map.get(opts, :current_path_prefix, "")

    Enum.reduce(keys, writer, fn key, acc ->
      encode_entry(acc, key, Map.get(map, key), depth, opts, path_prefix)
    end)
  end

  # Nested map entry — uses encode_to_lines to avoid the binary roundtrip.
  defp encode_map_entry(writer, key, value, depth, opts) do
    encoded_key = Strings.encode_key(key)
    header = [encoded_key, Constants.colon()]
    writer = Writer.push(writer, header, depth)

    current_prefix = Map.get(opts, :current_path_prefix, "")
    new_prefix = build_path_prefix(current_prefix, key)
    nested_opts = Map.put(opts, :current_path_prefix, new_prefix)
    nested_lines = encode_to_lines(value, depth + 1, nested_opts)

    append_lines(writer, nested_lines)
  end

  # Clause 1 — primitive final value
  defp encode_folded_value(writer, folded_key, final_value, depth, opts)
       when is_nil(final_value) or is_boolean(final_value) or
              is_number(final_value) or is_binary(final_value) do
    line = [
      folded_key,
      Constants.colon(),
      Constants.space(),
      Primitives.encode(final_value, opts.delimiter)
    ]

    Writer.push(writer, line, depth)
  end

  # Clause 2 — list (array) final value
  defp encode_folded_value(writer, folded_key, final_value, depth, opts)
       when is_list(final_value) do
    array_lines = Arrays.encode(folded_key, final_value, depth, opts)
    # 3-arg version — unchanged
    append_lines(writer, array_lines, depth)
  end

  # Clause 3 — empty map final value
  defp encode_folded_value(writer, folded_key, final_value, depth, _opts)
       when is_map(final_value) and map_size(final_value) == 0 do
    Writer.push(writer, [folded_key, Constants.colon()], depth)
  end

  # Clause 4 — non-empty map final value (UPDATED: uses encode_to_lines + append_lines/2)
  defp encode_folded_value(writer, folded_key, final_value, depth, opts)
       when is_map(final_value) do
    nested_opts = Map.put(opts, :flatten_depth, 0)
    header = [folded_key, Constants.colon()]
    writer = Writer.push(writer, header, depth)
    nested_lines = encode_to_lines(final_value, depth + 1, nested_opts)
    # 2-arg version from performance fix
    append_lines(writer, nested_lines)
  end

  # Clause 5 — fallback for any type not covered above (encodes as null)
  defp encode_folded_value(writer, folded_key, _final_value, depth, _opts) do
    Writer.push(
      writer,
      [folded_key, Constants.colon(), Constants.space(), Constants.null_literal()],
      depth
    )
  end

  # NEW helper — pushes pre-built line iodata directly into the writer.
  # Zero binary allocation vs the old append_iodata that did:
  #   IO.iodata_to_binary → String.split("\n") → Enum.reduce Writer.push
  #
  # Note: blank lines (empty iodata) are skipped to preserve the old
  # behaviour of append_iodata which filtered out empty strings.
  defp append_lines(writer, lines) do
    Enum.reduce(lines, writer, fn
      # skip empty lines produced by nested empty objects
      "", acc -> acc
      [], acc -> acc
      line, acc -> %{acc | lines: [line | acc.lines]}
    end)
  end

  # Collect all dotted keys that should prevent folding
  defp collect_forbidden_fold_paths(keys) do
    Enum.reduce(keys, MapSet.new(), fn key, acc ->
      if String.contains?(key, "."), do: MapSet.put(acc, key), else: acc
    end)
  end

  # Get keys in the correct order based on key_order option
  # Pattern 1: key_order is a map with path-specific ordering
  defp get_ordered_keys(map, key_order, path) when is_map(key_order) do
    case Map.fetch(key_order, path) do
      {:ok, ordered} ->
        Enum.filter(ordered, &Map.has_key?(map, &1))

      :error ->
        Map.keys(map) |> Enum.sort()
    end
  end

  # Pattern 2: key_order is a list at root level
  defp get_ordered_keys(map, key_order, [])
       when is_list(key_order) and key_order != [] do
    existing_keys = Map.keys(map)
    ordered_existing = Enum.filter(key_order, &(&1 in existing_keys))

    if length(ordered_existing) == length(existing_keys) do
      ordered_existing
    else
      Enum.sort(existing_keys)
    end
  end

  # Pattern 3: No key_order or not applicable - sort alphabetically
  defp get_ordered_keys(map, _key_order, _path) do
    Map.keys(map) |> Enum.sort()
  end

  @doc """
  Encodes a single key-value pair.
  """
  @spec encode_entry(Writer.t(), String.t(), term(), non_neg_integer(), map(), String.t()) ::
          Writer.t()
  def encode_entry(writer, key, value, depth, opts, path_prefix \\ "") do
    # Check for key folding
    if should_fold?(key, value, opts, path_prefix) do
      encode_folded_entry(writer, key, value, depth, opts)
    else
      encode_regular_entry(writer, key, value, depth, opts)
    end
  end

  # Pattern match on value types for better clarity
  defp encode_regular_entry(writer, key, value, depth, opts)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value) do
    encode_primitive_entry(writer, key, value, depth, opts)
  end

  defp encode_regular_entry(writer, key, value, depth, opts) when is_list(value) do
    array_lines = Arrays.encode(key, value, depth, opts)
    append_lines(writer, array_lines, depth)
  end

  defp encode_regular_entry(writer, key, value, depth, opts) when is_map(value) do
    encode_map_entry(writer, key, value, depth, opts)
  end

  defp encode_regular_entry(writer, key, _value, depth, opts) do
    encode_null_entry(writer, key, depth, opts)
  end

  # Helper functions for each entry type
  defp encode_primitive_entry(writer, key, value, depth, opts) do
    encoded_key = Strings.encode_key(key)

    line = [
      encoded_key,
      Constants.colon(),
      Constants.space(),
      Primitives.encode(value, opts.delimiter)
    ]

    Writer.push(writer, line, depth)
  end

  defp encode_null_entry(writer, key, depth, _opts) do
    encoded_key = Strings.encode_key(key)
    line = [encoded_key, Constants.colon(), Constants.space(), Constants.null_literal()]
    Writer.push(writer, line, depth)
  end

  defp build_path_prefix("", key), do: key
  defp build_path_prefix(prefix, key), do: prefix <> "." <> key

  # Check if we should fold this key-value pair into a dotted path
  defp should_fold?(key, value, opts, path_prefix) do
    case Map.get(opts, :key_folding, "off") do
      "safe" ->
        # Only fold single-key maps with valid identifier segments
        Utils.map?(value) and
          map_size(value) == 1 and
          valid_identifier_segment?(key) and
          flatten_depth_allows?(opts, 1) and
          not has_collision?(key, value, opts, path_prefix)

      _ ->
        false
    end
  end

  # Check if folding would create a collision with forbidden fold paths
  defp has_collision?(key, value, opts, path_prefix) do
    forbidden = Map.get(opts, :forbidden_fold_paths, MapSet.new())

    # Compute what the full folded path would be
    {path, _final_value} = collect_fold_path([key], value, %{flatten_depth: :infinity}, 1)
    local_folded = Enum.join(path, ".")

    # Build the full path from root
    full_folded_key =
      if path_prefix == "" do
        local_folded
      else
        path_prefix <> "." <> local_folded
      end

    # Check if the full folded path collides with any forbidden path
    MapSet.member?(forbidden, full_folded_key)
  end

  defp valid_identifier_segment?(key) do
    Regex.match?(@identifier_segment_pattern, key)
  end

  defp flatten_depth_allows?(opts, current_depth) do
    case Map.get(opts, :flatten_depth, :infinity) do
      :infinity -> true
      max when is_integer(max) -> current_depth <= max
    end
  end

  # Encode a folded key-value pair (collapse single-key chains)
  # Pattern match on final value type for clarity
  defp encode_folded_entry(writer, key, value, depth, opts) do
    {path, final_value} = collect_fold_path([key], value, opts, 1)
    folded_key = Enum.join(path, ".")

    encode_folded_value(writer, folded_key, final_value, depth, opts)
  end

  # Recursively collect the path for folding
  # Performance: Use accumulator pattern with [next_key | acc] instead of path ++ [next_key]
  # to avoid O(n²) list concatenation in deep fold chains

  # Pattern 1: Not a map - stop folding
  defp collect_fold_path(path, value, _opts, _current_depth) when not is_map(value) do
    {:lists.reverse(path), value}
  end

  # Pattern 2: Map with size != 1 - stop folding
  defp collect_fold_path(path, value, _opts, _current_depth)
       when is_map(value) and map_size(value) != 1 do
    {:lists.reverse(path), value}
  end

  # Pattern 3: Continue folding if conditions are met
  defp collect_fold_path(path, value, opts, current_depth) when is_map(value) do
    if flatten_depth_allows?(opts, current_depth + 1) do
      [{next_key, next_value}] = Map.to_list(value)

      if valid_identifier_segment?(next_key) do
        collect_fold_path([next_key | path], next_value, opts, current_depth + 1)
      else
        {:lists.reverse(path), value}
      end
    else
      {:lists.reverse(path), value}
    end
  end

  # Private helpers

  defp append_lines(writer, [header | data_rows], depth) do
    # For arrays, the first line is the header at current depth
    # Subsequent lines (data rows for tabular format) should be one level deeper
    writer = Writer.push(writer, header, depth)

    Enum.reduce(data_rows, writer, fn row, acc ->
      Writer.push(acc, row, depth + 1)
    end)
  end
end
