defmodule ToonEx.Decode.StructuralParserV2 do
  @moduledoc """
  Structural parser for TOON format that handles indentation-based nesting.

  This parser processes TOON input by analyzing indentation levels and building
  a hierarchical structure from the flat text representation.

  ## Performance Design (Jason-level efficiency)

  This parser is optimized for single-pass, zero-copy decoding:

  1. **Binary pattern matching** replaces `String.starts_with?`, `String.contains?`,
     `String.ends_with?`, and regex calls in hot paths with O(1) byte checks.
  2. **Sub-binary references** via `binary_part/3` avoid copying — BEAM shares
     the underlying binary when slicing.
  3. **Tail-recursive accumulators** with `:lists.reverse/1` instead of appending.
  4. **`@compile {:inline, ...}`** for hot functions to eliminate call overhead.
  5. **Struct pattern matching** in function heads replaces `cond` + map access.
  6. **`binary_part/3`** for slicing instead of `String.slice/3` (avoids UTF-8 scan).
  """

  alias ToonEx.Decode.Parser
  alias ToonEx.DecodeError

  # Performance: Direct binary constants to eliminate function call overhead
  @comma ","
  @tab "\t"
  @pipe "|"

  # Performance: Inline hot functions to reduce function call overhead during decoding
  @compile {:inline,
            parse_value: 1,
            do_parse_value: 1,
            parse_number_or_string: 1,
            unquote_string: 1,
            unquote_key: 1,
            extract_delimiter: 1,
            parse_fields: 2,
            parse_delimited_values: 2,
            remove_list_marker: 1,
            line_kind: 1,
            empty_list_item_value?: 1,
            build_map_with_keys: 2,
            build_map_from_fields_and_values: 3,
            normalize_parsed_number: 2,
            normalize_decimal_number: 1,
            has_decimal_or_exponent?: 1,
            detect_delimiter: 2,
            peek_next_indent: 1,
            get_first_content_indent: 1,
            key_was_quoted?: 1,
            add_key_to_metadata: 3,
            do_trim_leading: 1,
            do_trim_trailing: 1,
            do_contains_byte?: 2,
            do_find_colon_space: 1,
            do_ends_with_colon?: 1,
            do_starts_with_dash?: 1}

  # Pre-compiled regex patterns for performance - avoids recompilation on every call
  # These are used in non-hot-path locations where regex expressiveness is needed
  @tabular_array_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+.*\])\{([^}]+)\}:$/
  @root_tabular_array_regex ~r/^\[((\d+))([^\]]*)\]\{([^}]+)\}:$/
  @list_array_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+[^\]]*\]):$/
  @array_length_regex ~r/\[(\d+)/
  @array_header_with_values_regex ~r/\[(\d+)([^\]]*)\]$/
  @inline_array_header_regex ~r/^\[([^\]]+)\]:\s*(.*)$/
  @array_header_with_colon_regex ~r/^[\w"]+(\[(\d+)[^\]]*\]):/

  # Module-level regex patterns for structural matching (non-hot-path)
  @field_pattern ~r/^(?:"(?:[^"\\]|\\.)*"|[\w.-]+)(?:\[[^\]]*\])?\s*:/
  @tabular_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+.*\])\{([^}]+)\}:$/
  @list_array_regex ~r/^((?:"[^"]*"|[\w.]+))\[(\d+).*\]:$/

  @type line_info :: %{
          content: String.t(),
          indent: non_neg_integer(),
          line_number: non_neg_integer(),
          original: String.t(),
          is_blank: boolean()
        }

  @type parse_metadata :: %{
          quoted_keys: MapSet.t(String.t()),
          key_order: list(String.t())
        }

  @doc """
  Parses TOON input string into a structured format.

  Returns a tuple of {result, metadata} where metadata contains quoted_keys and key_order.
  """
  @spec parse(String.t(), map()) :: {:ok, {term(), parse_metadata()}} | {:error, DecodeError.t()}

  def parse(input, opts) when is_binary(input) do
    lines = preprocess_lines(input)

    if opts.strict, do: validate_indentation(lines, opts)

    initial_metadata = %{quoted_keys: MapSet.new(), key_order: []}

    {result, metadata} =
      case lines do
        [] -> {%{}, initial_metadata}
        _ -> parse_structure(lines, 0, opts, initial_metadata)
      end

    # Reverse once here — O(N) — instead of appending O(N) times above.
    final_metadata = %{metadata | key_order: :lists.reverse(metadata.key_order)}

    {:ok, {result, final_metadata}}
  rescue
    e in DecodeError ->
      {:error, e}

    e ->
      {:error,
       DecodeError.exception(message: "Parse failed: #{Exception.message(e)}", input: input)}
  end

  # Preprocess input into line information structures
  # Jason-style: :binary.split returns plain binaries (no String struct overhead),
  # tail-recursive preprocessing avoids intermediate Enum.with_index list.

  defp preprocess_lines(input) do
    input
    |> :binary.split("\n", [:global])
    |> do_preprocess_lines([], 1)
    |> drop_trailing_blank()
  end

  defp do_preprocess_lines([], acc, _idx), do: :lists.reverse(acc)

  defp do_preprocess_lines([line | rest], acc, idx) do
    do_preprocess_lines(rest, [build_line_info(line, idx) | acc], idx + 1)
  end

  # Jason-style: binary pattern matching for leading space counting.
  # Replaces String.trim_leading (which allocates a new binary) with a
  # single-pass scan that returns the sub-binary reference and count.
  # The sub-binary from pattern matching is O(1) — no copy.
  defp build_line_info(line, line_num) do
    {trimmed, indent} = trim_leading_spaces(line, 0)
    # Jason-style: binary scan for blank detection replaces String.trim_trailing
    # which would allocate a trimmed copy just to check if it's empty.
    is_blank = trimmed == "" or do_all_whitespace?(trimmed)
    %{content: trimmed, indent: indent, line_number: line_num, original: line, is_blank: is_blank}
  end

  # Strip leading spaces/tabs and count how many were removed.
  # Returns {rest_binary, count}.
  @compile {:inline, trim_leading_spaces: 2}
  defp trim_leading_spaces(<<?\s, rest::binary>>, count), do: trim_leading_spaces(rest, count + 1)
  defp trim_leading_spaces(<<?\t, rest::binary>>, count), do: trim_leading_spaces(rest, count + 1)
  defp trim_leading_spaces(rest, count), do: {rest, count}

  # Check if a binary contains only whitespace (spaces and tabs).
  # Replaces `String.trim_trailing(str) == ""` to avoid allocating a trimmed copy.
  @compile {:inline, do_all_whitespace?: 1}
  defp do_all_whitespace?(<<>>), do: true
  defp do_all_whitespace?(<<?\s, rest::binary>>), do: do_all_whitespace?(rest)
  defp do_all_whitespace?(<<?\t, rest::binary>>), do: do_all_whitespace?(rest)
  defp do_all_whitespace?(_), do: false

  defp drop_trailing_blank(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(fn line -> line.is_blank end)
    |> Enum.reverse()
  end

  defp validate_indentation(lines, opts) do
    indent_size = Map.get(opts, :indent_size, 2)

    Enum.each(lines, fn line ->
      unless line.is_blank do
        # Check for tab characters in INDENTATION first (before indent multiple check)
        # so that "Tab" errors are raised with the correct message
        if has_tab_in_leading_whitespace?(line.original) do
          raise DecodeError,
            message: "Tab characters are not allowed in indentation (strict mode)",
            input: line.original
        end

        # Check if indent is a multiple of indent_size
        if line.indent > 0 and rem(line.indent, indent_size) != 0 do
          raise DecodeError,
            message: "Indentation must be a multiple of #{indent_size} spaces (strict mode)",
            input: line.original
        end
      end
    end)
  end

  # Performance: Binary pattern matching instead of String.contains?
  defp has_tab_in_leading_whitespace?(<<?\t, _rest::binary>>), do: true

  defp has_tab_in_leading_whitespace?(<<?\s, rest::binary>>),
    do: has_tab_in_leading_whitespace?(rest)

  defp has_tab_in_leading_whitespace?(_), do: false

  defp parse_structure(lines, base_indent, opts, metadata) do
    {root_type, _} = detect_root_type(lines)

    case root_type do
      :root_array ->
        parse_root_array(lines, opts, metadata)

      :root_primitive ->
        parse_root_primitive(lines, opts, metadata)

      :object ->
        parse_object_lines(lines, base_indent, opts, metadata)
    end
  end

  # Detect if the root is an array or object or primitive
  # Performance: Uses pre-compiled module-level regexes instead of inline ~r patterns
  defp detect_root_type([%{content: content} | rest]) do
    cond do
      # Root array header patterns
      String.starts_with?(content, "[") ->
        {:root_array, :inline}

      String.match?(content, @root_tabular_array_regex) ->
        {:root_array, :tabular}

      # Single line -> check if it's a primitive or key-value
      rest == [] ->
        cond do
          # Tabular array header key[N]{fields}: ... — must be detected before
          # the generic key-value check because {fields} sits between [N] and ":"
          # and breaks the simpler regex.
          String.match?(content, @tabular_header_regex) ->
            # Route to :object so parse_entry_line raises DecodeError on the
            # missing / malformed data rows (4 declared, 0 present here).
            {:object, nil}

          # List array header key[N]: ... (inline value on header line is also invalid)
          String.match?(content, @list_array_regex) ->
            {:object, nil}

          # Normal key-value pair
          String.match?(content, @field_pattern) ->
            {:object, nil}

          true ->
            {:root_primitive, nil}
        end

      # Multiple lines -> object
      true ->
        {:object, nil}
    end
  end

  # Parse root primitive value (single value without key)

  defp parse_root_primitive([%{content: content}], _opts, metadata) do
    unless valid_primitive?(content) do
      raise DecodeError,
        message: "Invalid TOON value: #{inspect(content)}",
        input: content
    end

    {parse_value(content), metadata}
  end

  defp valid_primitive?(content) do
    case content do
      "null" -> true
      "true" -> true
      "false" -> true
      <<?", _rest::binary>> -> true
      _ -> do_valid_number_format?(content) or not do_contains_colon_comma_newline?(content)
    end
  end

  # Performance: Binary scan for colon/comma/newline — replaces String.contains?
  # Used by valid_primitive? to detect unquoted strings (valid if no :, ,, \n, \r)
  defp do_contains_colon_comma_newline?(<<>>), do: false
  defp do_contains_colon_comma_newline?(<<?:, _rest::binary>>), do: true
  defp do_contains_colon_comma_newline?(<<?,, _rest::binary>>), do: true
  defp do_contains_colon_comma_newline?(<<?\n, _rest::binary>>), do: true
  defp do_contains_colon_comma_newline?(<<?\r, _rest::binary>>), do: true

  defp do_contains_colon_comma_newline?(<<_byte, rest::binary>>),
    do: do_contains_colon_comma_newline?(rest)

  # Performance: Binary scan for valid number format
  defp do_valid_number_format?(<<>>), do: false
  defp do_valid_number_format?(<<?-, rest::binary>>), do: do_valid_number_digits?(rest)

  defp do_valid_number_format?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_digits?(rest)

  defp do_valid_number_format?(_), do: false

  defp do_valid_number_digits?(<<>>), do: true

  defp do_valid_number_digits?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_digits?(rest)

  defp do_valid_number_digits?(<<?., rest::binary>>), do: do_valid_number_frac?(rest)

  defp do_valid_number_digits?(<<c, rest::binary>>) when c == ?e or c == ?E,
    do: do_valid_number_exp_sign?(rest)

  defp do_valid_number_digits?(_), do: false

  defp do_valid_number_frac?(<<>>), do: false

  defp do_valid_number_frac?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_exp_sign?(rest)

  defp do_valid_number_frac?(_), do: false

  defp do_valid_number_exp_sign?(<<>>), do: true

  defp do_valid_number_exp_sign?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_exp_sign?(rest)

  defp do_valid_number_exp_sign?(<<?e, rest::binary>>), do: do_valid_number_exp_digits?(rest)
  defp do_valid_number_exp_sign?(<<?E, rest::binary>>), do: do_valid_number_exp_digits?(rest)
  defp do_valid_number_exp_sign?(_), do: false

  defp do_valid_number_exp_digits?(<<>>), do: false

  defp do_valid_number_exp_digits?(<<?+, rest::binary>>),
    do: do_valid_number_exp_digits_final?(rest)

  defp do_valid_number_exp_digits?(<<?-, rest::binary>>),
    do: do_valid_number_exp_digits_final?(rest)

  defp do_valid_number_exp_digits?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_exp_digits_final?(rest)

  defp do_valid_number_exp_digits?(_), do: false

  defp do_valid_number_exp_digits_final?(<<>>), do: true

  defp do_valid_number_exp_digits_final?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_exp_digits_final?(rest)

  defp do_valid_number_exp_digits_final?(_), do: false

  defp parse_root_array([%{content: header_line} = line_info | rest], opts, metadata) do
    cond do
      # Root inline array: [2]: a,b
      String.starts_with?(header_line, "[") and String.contains?(header_line, "]: ") ->
        {result, meta} = parse_root_inline_array(header_line, opts)
        {result, Map.merge(metadata, meta)}

      # Root tabular array: [2]{name,age}: ...
      String.match?(header_line, @root_tabular_array_regex) ->
        result = parse_tabular_array_data(header_line, rest, 0, opts)
        {result, metadata}

      # Root list array: [2]: (with nested items)
      String.starts_with?(header_line, "[") ->
        parse_complex_root_array(line_info, rest, opts, metadata)

      true ->
        parse_object_lines([line_info | rest], 0, opts, metadata)
    end
  end

  defp parse_complex_root_array(%{content: header}, rest, opts, metadata) do
    case Regex.run(@root_tabular_array_regex, header) do
      [_, _full_length, length_str, delimiter_marker, fields_str] ->
        declared_length = String.to_integer(length_str)
        delimiter = extract_delimiter("[#{delimiter_marker}]")
        fields = parse_fields(fields_str, delimiter)
        data_rows = take_nested_lines(rest, 0)

        if length(data_rows) != declared_length do
          raise DecodeError,
            message:
              "Tabular array row count mismatch: declared #{declared_length}, got #{length(data_rows)}",
            input: header
        end

        array_data = parse_tabular_data_rows(data_rows, fields, delimiter, opts)
        {array_data, metadata}

      nil ->
        # Root list array: [N]: with nested list items
        case Regex.run(@array_length_regex, header) do
          [_, length_str] ->
            declared_length = String.to_integer(length_str)
            items = parse_list_array_items(rest, 0, opts)

            if Map.get(opts, :strict, true) && length(items) != declared_length do
              raise DecodeError,
                message:
                  "Array length mismatch: declared #{declared_length}, got #{length(items)}",
                input: header
            end

            {items, metadata}

          nil ->
            raise DecodeError, message: "Invalid root array header", input: header
        end
    end
  end

  defp parse_root_inline_array(header, _opts) do
    case Regex.run(@inline_array_header_regex, header) do
      [_, array_marker, values_str] ->
        delimiter = extract_delimiter(array_marker)

        values =
          if values_str == "" do
            []
          else
            parse_delimited_values(values_str, delimiter)
          end

        {values, %{quoted_keys: MapSet.new(), key_order: []}}

      nil ->
        raise DecodeError, message: "Invalid inline array header", input: header
    end
  end

  defp build_map_with_keys(entries, opts) do
    case opts.keys do
      :strings -> :maps.from_list(entries)
      :atoms -> Map.new(entries, fn {k, v} -> {String.to_atom(k), v} end)
      :atoms! -> Map.new(entries, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end
  end

  # Performance: Build map directly from parallel field/value lists without intermediate zip
  defp build_map_from_fields_and_values(fields, values, opts) do
    case opts.keys do
      :strings ->
        :maps.from_list(:lists.zip(fields, values))

      :atoms ->
        :maps.from_list(
          :lists.zipwith(
            fn k, v -> {String.to_atom(k), v} end,
            fields,
            values
          )
        )

      :atoms! ->
        :maps.from_list(
          :lists.zipwith(
            fn k, v -> {String.to_existing_atom(k), v} end,
            fields,
            values
          )
        )
    end
  end

  # Parse object from lines
  defp parse_object_lines(lines, base_indent, opts, metadata) do
    {entries, _remaining, updated_metadata} = parse_entries(lines, base_indent, opts, metadata)

    {build_map_with_keys(entries, opts), updated_metadata}
  end

  # Performance: Struct pattern matching in function heads replaces cond + map access.
  # Each clause is a direct pattern match on the line_info struct fields,
  # eliminating the overhead of map access + comparison in a cond block.
  # BEAM optimizes function-head pattern matches into O(1) dispatch.

  defp parse_entries([], _base_indent, _opts, metadata), do: {[], [], metadata}

  # Skip blank lines (only at root level or when not strict)
  defp parse_entries([%{is_blank: true} | rest], base_indent, opts, metadata) do
    parse_entries(rest, base_indent, opts, metadata)
  end

  # Skip lines that are less indented (parent level)
  defp parse_entries([%{indent: indent} | _] = lines, base_indent, _opts, metadata)
       when indent < base_indent do
    {[], lines, metadata}
  end

  # Skip lines that are more indented (will be handled by parent)
  defp parse_entries([%{indent: indent} | _] = lines, base_indent, _opts, metadata)
       when indent > base_indent do
    {[], lines, metadata}
  end

  # Process line at current level
  defp parse_entries([line | rest], base_indent, opts, metadata) do
    case parse_entry_line(line, rest, base_indent, opts, metadata) do
      {:entry, key, value, remaining, updated_metadata} ->
        {entries, final_remaining, final_metadata} =
          parse_entries(remaining, base_indent, opts, updated_metadata)

        {[{key, value} | entries], final_remaining, final_metadata}

      {:skip, remaining, updated_metadata} ->
        parse_entries(remaining, base_indent, opts, updated_metadata)
    end
  end

  # Parse a single entry line
  defp parse_entry_line(%{content: content} = line_info, rest, base_indent, opts, metadata) do
    # Track if key was quoted by checking if line starts with quote
    was_quoted = key_was_quoted?(content)

    case Parser.parse_line(content) do
      {:ok, [result], "", _, _, _} ->
        case result do
          {key, value} when is_list(value) ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            # Check if this is an empty array with nested content (list or tabular format)
            # Pattern like items[3]: with indented lines following
            if value == [] and peek_next_indent(rest) > base_indent do
              # This is a list/tabular array header, not an inline array
              # Fall through to special line handling
              case handle_special_line(line_info, rest, base_indent, opts, updated_meta) do
                {:skip, _, updated_meta2} ->
                  # If special line handling doesn't work, treat as empty array
                  {:entry, key, [], rest, updated_meta2}

                result ->
                  result
              end
            else
              # Inline array - ALWAYS re-parse to respect leading zeros and other edge cases
              # The Parser module may have already parsed numbers incorrectly
              # Extract array marker from content to get delimiter
              corrected_value =
                case Regex.run(@array_header_with_colon_regex, content) do
                  [_, array_marker, length_str] ->
                    declared_length = String.to_integer(length_str)
                    delimiter = extract_delimiter(array_marker)
                    # Re-parse the values with correct delimiter
                    case do_find_colon_space(content) do
                      {:found, pos} ->
                        values_str = binary_part(content, pos + 2, byte_size(content) - pos - 2)
                        values = parse_delimited_values(values_str, delimiter)

                        # Validate length (strict mode only per TOON spec Section 14.1)
                        if Map.get(opts, :strict, true) && length(values) != declared_length do
                          raise DecodeError,
                            message:
                              "Array length mismatch: declared #{declared_length}, got #{length(values)}",
                            input: content
                        end

                        values

                      :not_found ->
                        value
                    end

                  _ ->
                    value
                end

              {:entry, key, corrected_value, rest, updated_meta}
            end

          {key, value} ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            case peek_next_indent(rest) do
              indent when indent > base_indent ->
                {nested_value, nested_meta} =
                  parse_nested_value(key, rest, base_indent, opts, updated_meta)

                {remaining_lines, _} = skip_nested_lines(rest, base_indent)

                {:entry, key, nested_value, remaining_lines, nested_meta}

              _ ->
                # FIX: When the raw value string is empty (e.g. "key: "), preserve
                # the Parser's result (%{} from empty_kv) instead of calling
                # parse_value(""), which would incorrectly return "".
                corrected_value =
                  case do_find_colon_space(content) do
                    {:found, pos} ->
                      value_str = binary_part(content, pos + 2, byte_size(content) - pos - 2)
                      trimmed_str = do_trim_leading(value_str) |> do_trim_trailing()

                      if trimmed_str == "", do: value, else: parse_value(trimmed_str)

                    :not_found ->
                      value
                  end

                {:entry, key, corrected_value, rest, updated_meta}
            end
        end

      {:ok, [parsed_result], rest_content, _, _, _} when rest_content != "" ->
        case parsed_result do
          {key, _partial_value} ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            case do_find_colon_space(content) do
              {:found, pos} ->
                array_header = binary_part(content, 0, pos)
                values_str = binary_part(content, pos + 2, byte_size(content) - pos - 2)

                # Re-parse as array if header contains [N]
                case Regex.run(@array_header_with_values_regex, array_header) do
                  [_, length_str, delimiter_marker] ->
                    declared_length = String.to_integer(length_str)
                    delimiter = extract_delimiter("[#{delimiter_marker}]")
                    values = parse_delimited_values(values_str, delimiter)

                    # Validate length (strict mode only per TOON spec Section 14.1)
                    if Map.get(opts, :strict, true) && length(values) != declared_length do
                      raise DecodeError,
                        message:
                          "Array length mismatch: declared #{declared_length}, got #{length(values)}",
                        input: content
                    end

                    {:entry, key, values, rest, updated_meta}

                  nil ->
                    # Not an array line — original scalar fallback
                    full_value = parse_value(do_trim_leading(values_str) |> do_trim_trailing())
                    {:entry, key, full_value, rest, updated_meta}
                end

              :not_found ->
                {:skip, rest, metadata}
            end

          _ ->
            {:skip, rest, metadata}
        end

      {:ok, _, _, _, _, _} ->
        # Unexpected parse result
        {:skip, rest, metadata}

      {:error, reason, _, _, _, _} ->
        # Try to handle special cases like array headers
        # If it still fails, raise an error
        case handle_special_line(line_info, rest, base_indent, opts, metadata) do
          {:skip, _, _meta} ->
            raise DecodeError,
              message: "Failed to parse line: #{reason}",
              input: content

          result ->
            result
        end
    end
  end

  # Performance: Binary scan for ": " (colon-space) pattern.
  # Replaces String.split(content, ": ", parts: 2) which allocates a list of strings.
  # Returns {:found, byte_position} or :not_found.
  @compile {:inline, do_find_colon_space: 1}
  defp do_find_colon_space(binary), do: do_find_colon_space(binary, 0)

  defp do_find_colon_space(<<?:, ?\s, _rest::binary>>, pos), do: {:found, pos}
  defp do_find_colon_space(<<_byte, rest::binary>>, pos), do: do_find_colon_space(rest, pos + 1)
  defp do_find_colon_space(<<>>, _pos), do: :not_found

  # Performance: Binary scan for a specific byte value.
  # Replaces String.contains?(str, char) — avoids String overhead.
  @compile {:inline, do_contains_byte?: 2}
  defp do_contains_byte?(<<>>, _byte), do: false
  defp do_contains_byte?(<<byte, _rest::binary>>, byte), do: true
  defp do_contains_byte?(<<_other, rest::binary>>, byte), do: do_contains_byte?(rest, byte)

  # Performance: Check if binary ends with a specific byte.
  # Replaces String.ends_with?(str, ":") — O(1) via :binary.last instead of O(n) suffix check.
  @compile {:inline, do_ends_with_colon?: 1}
  defp do_ends_with_colon?(<<>>), do: false
  defp do_ends_with_colon?(binary) when is_binary(binary), do: :binary.last(binary) == ?:

  # Performance: Check if trimmed content starts with dash marker.
  # Replaces String.starts_with?(String.trim_leading(content), "-")
  @compile {:inline, do_starts_with_dash?: 1}
  defp do_starts_with_dash?(<<?\s, rest::binary>>), do: do_starts_with_dash?(rest)
  defp do_starts_with_dash?(<<?\t, rest::binary>>), do: do_starts_with_dash?(rest)
  defp do_starts_with_dash?(<<?-, _rest::binary>>), do: true
  defp do_starts_with_dash?(_), do: false

  # Performance: Binary pattern matching replaces regex in hot-path line_kind/1.
  #
  # TOON structural markers:
  #   Tabular array: key[N]{fields}:  → ends with "}:"
  #   List array:    key[N]:          → ends with "]:"
  #   Nested object: key:             → ends with ":" and no space
  #
  # By checking the last 1-2 bytes first (O(1)), we short-circuit the
  # vast majority of lines that don't match any special pattern.
  # The `do_contains_byte?(content, ?[)` check for list/tabular is a
  # safety net to prevent false positives on values like `result: ]:`.
  defp line_kind(content) do
    size = byte_size(content)

    if size >= 2 do
      last = :binary.last(content)

      if last == ?: do
        second_last = :binary.first(binary_part(content, size - 2, 1))

        cond do
          # Tabular array: key[N]{fields}: → ends with "}:" and contains "["
          second_last == ?} and do_contains_byte?(content, ?[) ->
            :tabular_array

          # List array: key[N]: → ends with "]:" and contains "["
          second_last == ?] and do_contains_byte?(content, ?[) ->
            :list_array

          # Nested object: key: → ends with ":" and no space in content
          not do_contains_byte?(content, ?\s) ->
            :nested_object

          true ->
            :unknown
        end
      else
        :unknown
      end
    else
      if size == 1 and :binary.first(content) == ?: do
        :nested_object
      else
        :unknown
      end
    end
  end

  # Handle special line formats (array headers, etc.)
  defp handle_special_line(%{content: content} = line_info, rest, base_indent, opts, meta) do
    case line_kind(content) do
      :tabular_array -> parse_tabular_array_entry(line_info, rest, base_indent, opts, meta)
      :list_array -> parse_list_array_entry(line_info, rest, base_indent, opts, meta)
      :nested_object -> parse_nested_object_entry(content, rest, base_indent, opts, meta)
      :unknown -> {:skip, rest, meta}
    end
  end

  defp parse_tabular_array_entry(line_info, rest, base_indent, opts, metadata) do
    {{key, array_value}, updated_meta} =
      parse_tabular_array(line_info, rest, base_indent, opts, metadata)

    {remaining, _} = skip_nested_lines(rest, base_indent)
    {:entry, key, array_value, remaining, updated_meta}
  end

  defp parse_list_array_entry(line_info, rest, base_indent, opts, metadata) do
    {{key, array_value}, updated_meta} =
      parse_list_array(line_info, rest, base_indent, opts, metadata)

    {remaining, _} = skip_nested_lines(rest, base_indent)
    {:entry, key, array_value, remaining, updated_meta}
  end

  # Performance: Binary pattern matching for stripping trailing colon.
  # Replaces String.trim_trailing(content, ":") which allocates a new binary.
  # binary_part/3 creates an O(1) sub-binary reference — zero-copy.
  defp parse_nested_object_entry(content, rest, base_indent, opts, metadata) do
    key =
      content
      |> do_strip_trailing_colon()
      |> unquote_key()

    was_quoted = key_was_quoted?(content)
    updated_meta = add_key_to_metadata(key, was_quoted, metadata)

    case peek_next_indent(rest) do
      indent when indent > base_indent ->
        {nested_value, nested_meta} = parse_nested_object(rest, base_indent, opts, updated_meta)
        {remaining, _} = skip_nested_lines(rest, base_indent)
        {:entry, key, nested_value, remaining, nested_meta}

      _ ->
        {:entry, key, %{}, rest, updated_meta}
    end
  end

  # Strip trailing colon from binary — O(1) sub-binary via binary_part
  @compile {:inline, do_strip_trailing_colon: 1}
  defp do_strip_trailing_colon(binary) do
    size = byte_size(binary)

    if size > 0 and :binary.last(binary) == ?: do
      binary_part(binary, 0, size - 1)
    else
      binary
    end
  end

  # Parse nested value (object or array)
  defp parse_nested_value(_key, lines, base_indent, opts, metadata) do
    nested_lines = take_nested_lines(lines, base_indent)

    # Use the actual indent of the first nested line, not base_indent + indent_size
    # This allows non-multiple indentation when strict=false
    actual_indent = get_first_content_indent(nested_lines)
    parse_object_lines(nested_lines, actual_indent, opts, metadata)
  end

  # Parse nested object
  defp parse_nested_object(lines, base_indent, opts, metadata) do
    nested_lines = take_nested_lines(lines, base_indent)
    # Use the actual indent of the first nested line, not base_indent + indent_size
    actual_indent = get_first_content_indent(nested_lines)
    parse_object_lines(nested_lines, actual_indent, opts, metadata)
  end

  # Parse tabular array
  defp parse_tabular_array(%{content: header}, rest, base_indent, opts, metadata) do
    case Regex.run(@tabular_array_header_regex, header) do
      [_, raw_key, array_marker, fields_str] ->
        key = unquote_key(raw_key)
        was_quoted = key_was_quoted?(header)
        updated_meta = add_key_to_metadata(key, was_quoted, metadata)

        delimiter = extract_delimiter(array_marker)
        fields = parse_fields(fields_str, delimiter)

        # Extract declared length from array_marker
        declared_length =
          case Regex.run(@array_length_regex, array_marker) do
            [_, len_str] -> String.to_integer(len_str)
            nil -> nil
          end

        data_rows = take_nested_lines(rest, base_indent)

        # Validate row count when a length was declared (always the case in TOON)
        if declared_length != nil and length(data_rows) != declared_length do
          raise DecodeError,
            message:
              "Tabular array row count mismatch: declared #{declared_length}, got #{length(data_rows)}",
            input: header
        end

        array_data = parse_tabular_data_rows(data_rows, fields, delimiter, opts)
        {{key, array_data}, updated_meta}

      nil ->
        raise DecodeError, message: "Invalid tabular array header", input: header
    end
  end

  # Performance: Tail-recursive row builder with accumulator list + :lists.reverse.
  # Replaces Enum.reduce which creates intermediate list append operations.
  # Uses :lists.reverse/1 once at the end — O(N) total instead of O(N²) appending.
  defp parse_tabular_data_rows(lines, fields, delimiter, opts) do
    field_count = length(fields)
    do_parse_tabular_rows(lines, fields, field_count, delimiter, opts, [])
  end

  defp do_parse_tabular_rows([], _fields, _field_count, _delimiter, _opts, acc) do
    :lists.reverse(acc)
  end

  defp do_parse_tabular_rows([line | rest], fields, field_count, delimiter, opts, acc) do
    if line.is_blank do
      if opts.strict do
        raise DecodeError,
          message: "Blank lines are not allowed inside arrays in strict mode",
          input: line.original
      end

      do_parse_tabular_rows(rest, fields, field_count, delimiter, opts, acc)
    else
      values = parse_delimited_values(line.content, delimiter)

      if length(values) != field_count do
        raise DecodeError,
          message: "Row value count mismatch: expected #{field_count}, got #{length(values)}",
          input: line.content
      end

      # Build map directly from zipped fields and values
      row_map = build_map_from_fields_and_values(fields, values, opts)
      do_parse_tabular_rows(rest, fields, field_count, delimiter, opts, [row_map | acc])
    end
  end

  # Parse tabular array data (for root arrays)
  defp parse_tabular_array_data(header, rest, base_indent, opts) do
    case Regex.run(@root_tabular_array_regex, header) do
      [_, _full_length, length_str, delimiter_marker, fields_str] ->
        declared_length = String.to_integer(length_str)
        delimiter = extract_delimiter("[#{delimiter_marker}]")
        fields = parse_fields(fields_str, delimiter)
        data_rows = take_nested_lines(rest, base_indent)

        # Validate row count
        if length(data_rows) != declared_length do
          raise DecodeError,
            message:
              "Tabular array row count mismatch: declared #{declared_length}, got #{length(data_rows)}",
            input: header
        end

        parse_tabular_data_rows(data_rows, fields, delimiter, opts)

      nil ->
        raise DecodeError, message: "Invalid tabular array header", input: header
    end
  end

  # Parse list array
  defp parse_list_array(%{content: header}, rest, base_indent, opts, metadata) do
    case Regex.run(@list_array_header_regex, header) do
      [_, raw_key, array_marker] ->
        length_str =
          case Regex.run(@array_length_regex, array_marker) do
            [_, len] -> len
            nil -> "0"
          end

        declared_length = String.to_integer(length_str)
        key = unquote_key(raw_key)
        was_quoted = key_was_quoted?(header)
        updated_meta = add_key_to_metadata(key, was_quoted, metadata)

        # Extract delimiter from array marker and pass through opts
        delimiter = extract_delimiter(array_marker)
        opts_with_delimiter = Map.put(opts, :delimiter, delimiter)

        items = parse_list_array_items(rest, base_indent, opts_with_delimiter)

        # Validate item count (strict mode only per TOON spec Section 14.1)
        if Map.get(opts, :strict, true) && length(items) != declared_length do
          raise DecodeError,
            message: "Array length mismatch: declared #{declared_length}, got #{length(items)}",
            input: header
        end

        {{key, items}, updated_meta}

      nil ->
        raise DecodeError, message: "Invalid list array header", input: header
    end
  end

  # Parse list array items
  defp parse_list_array_items(lines, base_indent, opts) do
    list_lines = take_nested_lines(lines, base_indent)
    # Use the actual indent of the first list item, not base_indent + indent_size
    actual_indent = get_first_content_indent(list_lines)

    parse_list_items(list_lines, actual_indent, opts, [])
  end

  # Performance: Struct pattern matching in function heads replaces cond + map access.
  # Blank line check is the first clause (most common skip case).
  # Binary pattern matching replaces String.starts_with?/String.contains?.

  defp parse_list_items([], _expected_indent, _opts, acc), do: :lists.reverse(acc)

  # Skip blank lines (validate in strict mode if within array content)
  defp parse_list_items([%{is_blank: true} = line | rest], expected_indent, opts, acc) do
    if opts.strict do
      raise DecodeError,
        message: "Blank lines are not allowed inside arrays in strict mode",
        input: line.original
    else
      parse_list_items(rest, expected_indent, opts, acc)
    end
  end

  # Inline array item with values on same line: - [N]: val1,val2
  # Performance: Binary pattern matching replaces String.contains? + String.starts_with?
  defp parse_list_items([%{content: content} = line | rest], expected_indent, opts, acc)
       when is_binary(content) do
    trimmed_leading = do_trim_leading(content)

    cond do
      # Inline array item: starts with "- [" and contains "]: "
      byte_size(trimmed_leading) > 2 and
        binary_part(trimmed_leading, 0, 2) == "- [" and
          do_contains_byte?(trimmed_leading, ?:) ->
        {item, remaining} = parse_inline_array_item(line, rest, expected_indent, opts)
        parse_list_items(remaining, expected_indent, opts, [item | acc])

      # List item marker (with space "- " or just "-")
      binary_part(trimmed_leading, 0, 1) == "-" ->
        {item, remaining} = parse_list_item(line, rest, expected_indent, opts)
        parse_list_items(remaining, expected_indent, opts, [item | acc])

      true ->
        parse_list_items(rest, expected_indent, opts, acc)
    end
  end

  # Performance: Binary pattern matching replaces String.trim_leading + String.replace_prefix.
  # Scans past leading whitespace, then strips "- " or "-" prefix in one pass.
  # Returns a sub-binary reference (zero-copy) instead of allocating new strings.
  @compile {:inline, remove_list_marker: 1}
  defp remove_list_marker(content) do
    content
    |> do_trim_leading()
    |> do_strip_dash_prefix()
  end

  # Strip "- " or "-" prefix from binary — O(1) sub-binary via binary_part
  @compile {:inline, do_strip_dash_prefix: 1}
  defp do_strip_dash_prefix(<<?-, ?\s, rest::binary>>), do: rest
  defp do_strip_dash_prefix(<<?-, rest::binary>>), do: rest
  defp do_strip_dash_prefix(binary), do: binary

  # Parse a single list item
  defp parse_list_item(%{content: content} = line, rest, expected_indent, opts) do
    trimmed = remove_list_marker(content)
    route_list_item(trimmed, rest, line, expected_indent, opts)
  end

  defp route_list_item("", rest, _line, _expected_indent, _opts), do: {%{}, rest}

  defp route_list_item(trimmed, rest, line, expected_indent, opts) do
    cond do
      # Performance: Binary scan for whitespace replaces String.trim(trimmed) == ""
      do_is_only_whitespace?(trimmed) ->
        {%{}, rest}

      # Performance: Binary pattern matching for inline array detection
      # Replaces String.match?(trimmed, @inline_array_pattern)
      do_is_inline_array?(trimmed) ->
        parse_inline_array_from_line(trimmed, rest)

      # Performance: Binary pattern matching for list array header detection
      # Replaces String.match?(trimmed, @list_array_header_pattern)
      do_is_list_array_header?(trimmed) ->
        parse_nested_list_array(trimmed, rest, line, expected_indent, opts)

      line_kind(trimmed) == :tabular_array ->
        parse_list_item_with_array(trimmed, rest, line, expected_indent, opts, :tabular)

      line_kind(trimmed) == :list_array ->
        parse_list_item_with_array(trimmed, rest, line, expected_indent, opts, :list)

      true ->
        parse_list_item_normal(trimmed, rest, line, expected_indent, opts)
    end
  end

  # Performance: Binary scan for whitespace-only content.
  # Replaces String.trim(trimmed) == "" — avoids allocating a trimmed copy.
  @compile {:inline, do_is_only_whitespace?: 1}
  defp do_is_only_whitespace?(<<>>), do: true
  defp do_is_only_whitespace?(<<?\s, rest::binary>>), do: do_is_only_whitespace?(rest)
  defp do_is_only_whitespace?(<<?\t, rest::binary>>), do: do_is_only_whitespace?(rest)
  defp do_is_only_whitespace?(_), do: false

  # Performance: Binary pattern matching for inline array detection.
  # Inline array pattern: starts with "[" and contains "]: "
  # Replaces String.match?(trimmed, @inline_array_pattern) which compiles + runs regex.
  @compile {:inline, do_is_inline_array?: 1}
  defp do_is_inline_array?(<<?[, rest::binary>>), do: do_has_bracket_colon_space?(rest)
  defp do_is_inline_array?(_), do: false

  # Scan for "]: " pattern (closing bracket + colon + space)
  defp do_has_bracket_colon_space?(<<?], ?:, ?\s, _rest::binary>>), do: true
  defp do_has_bracket_colon_space?(<<_byte, rest::binary>>), do: do_has_bracket_colon_space?(rest)
  defp do_has_bracket_colon_space?(<<>>), do: false

  # Performance: Binary pattern matching for list array header detection.
  # List array header pattern: starts with "[" and ends with "]:" (no value after colon)
  # Replaces String.match?(trimmed, @list_array_header_pattern)
  @compile {:inline, do_is_list_array_header?: 1}
  defp do_is_list_array_header?(<<?[, _rest::binary>> = binary) do
    size = byte_size(binary)

    size >= 2 and :binary.last(binary) == ?: and
      :binary.first(binary_part(binary, size - 2, 1)) == ?]
  end

  defp do_is_list_array_header?(_), do: false

  defp parse_list_item_normal(trimmed, rest, line, expected_indent, opts) do
    delimiter = Map.get(opts, :delimiter, ",")

    result = Parser.parse_line(trimmed)

    case result do
      {:ok, [result], "", _, _, _} ->
        handle_complete_parse(result, trimmed, rest, line, expected_indent, opts)

      {:ok, [{key, partial_value}], remaining_input, _, _, _}
      when is_binary(remaining_input) and remaining_input != "" ->
        handle_partial_parse(
          key,
          partial_value,
          remaining_input,
          delimiter,
          trimmed,
          rest,
          line,
          expected_indent,
          opts
        )

      {:error, _, _, _, _, _} ->
        handle_parse_error(trimmed, rest, expected_indent, opts)
    end
  end

  defp handle_partial_parse(
         key,
         partial_value,
         remaining_input,
         delimiter,
         trimmed,
         rest,
         line,
         expected_indent,
         opts
       ) do
    # Performance: Binary pattern matching replaces String.starts_with?
    if delimiter != "," and binary_part(remaining_input, 0, 1) == "," do
      full_value = parse_value(to_string(partial_value) <> remaining_input)

      continuation_lines = take_item_lines(rest, expected_indent)

      item_indent =
        if length(continuation_lines) > 0,
          do: continuation_lines |> Enum.map(& &1.indent) |> Enum.min(),
          else: line.indent

      adjusted_content = "#{key}: #{full_value}"
      item_lines = [%{line | content: adjusted_content, indent: item_indent} | continuation_lines]
      empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
      {object, _} = parse_object_lines(item_lines, item_indent, opts, empty_metadata)
      remaining = Enum.drop(rest, length(continuation_lines))
      {object, remaining}
    else
      handle_complete_parse({key, partial_value}, trimmed, rest, line, expected_indent, opts)
    end
  end

  # handle_complete_parse/6
  #
  # Builds a map object from a parsed list-item result plus its continuation lines.
  #
  # Design: use line.indent as the base for parse_object_lines so that standard
  # TOON indentation-based nesting works correctly inside list items.
  #
  #   - args:           ← line.indent = 2
  #     device_id: val  ← continuation at indent 4
  #
  # With base = line.indent = 2: peek_next_indent = 4 > 2 → nesting triggered
  # → %{"args" => %{"device_id" => val}} ✓
  #
  # For non-empty valued first fields (e.g. "budget: 500 USD"), the
  # continuation lines are siblings.  We normalise all of them (including the
  # first line) to cont_indent so they share one base level and none triggers
  # spurious nesting via peek_next_indent.

  defp handle_complete_parse(result, trimmed, rest, line, expected_indent, opts) do
    case result do
      {_key, value} ->
        continuation_lines = take_item_lines(rest, expected_indent)

        {item_lines, item_indent} =
          if empty_list_item_value?(value) and continuation_lines != [] do
            cont_indent = continuation_lines |> Enum.map(& &1.indent) |> Enum.min()
            # Length of the list marker that was stripped from line.content
            # ("- " → 2, "-" → 1).  trimmed = remove_list_marker(line.content).
            marker_len = byte_size(line.content) - byte_size(trimmed)
            sibling_indent = line.indent + marker_len

            if cont_indent > sibling_indent do
              # Continuation lines are CHILDREN of this key (deeper than sibling
              # level).  Preserve line.indent so peek_next_indent detects nesting.
              {[%{line | content: trimmed} | continuation_lines], line.indent}
            else
              # Continuation lines are SIBLINGS (same logical indent as this key).
              # Normalise first-line indent to cont_indent so all fields share
              # the same base level in parse_object_lines.
              {[%{line | content: trimmed, indent: cont_indent} | continuation_lines],
               cont_indent}
            end
          else
            # Normal (non-empty) value: all continuation lines are siblings.
            cont_indent =
              if continuation_lines == [],
                do: line.indent,
                else: continuation_lines |> Enum.map(& &1.indent) |> Enum.min()

            {[%{line | content: trimmed, indent: cont_indent} | continuation_lines], cont_indent}
          end

        empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
        {object, _} = parse_object_lines(item_lines, item_indent, opts, empty_metadata)
        remaining = Enum.drop(rest, length(continuation_lines))
        {object, remaining}

      value ->
        {value, rest}
    end
  end

  # Only %{} (the empty_kv placeholder) represents "no value supplied".
  # nil (null literal) and "" (explicit quoted empty string) are real values
  # and must NOT trigger the children/sibling disambiguation path.
  defp empty_list_item_value?(value) when is_map(value) and map_size(value) == 0, do: true
  defp empty_list_item_value?(_), do: false

  defp handle_parse_error(trimmed, rest, expected_indent, opts) do
    # Performance: Binary pattern matching replaces String.ends_with? + String.contains?
    if do_ends_with_colon?(trimmed) and not do_contains_byte?(trimmed, ?\s) do
      next_indent = peek_next_indent(rest)

      if next_indent > expected_indent do
        parse_nested_key_with_content(trimmed, rest, next_indent, expected_indent, opts)
      else
        {parse_value(trimmed), rest}
      end
    else
      # Strip trailing delimiter comma — it is separator noise, not value data.
      # Performance: Binary pattern matching replaces String.trim_trailing(trimmed, ",")
      value_str = do_strip_trailing_commas(trimmed)
      {parse_value(value_str), rest}
    end
  end

  # Performance: Strip trailing commas via binary scan — replaces String.trim_trailing/2
  @compile {:inline, do_strip_trailing_commas: 1}
  defp do_strip_trailing_commas(binary) do
    size = byte_size(binary)

    if size > 0 and :binary.last(binary) == ?, do
      do_strip_trailing_commas(binary_part(binary, 0, size - 1))
    else
      binary
    end
  end

  defp parse_nested_key_with_content(trimmed, rest, _next_indent, expected_indent, opts) do
    # Performance: Binary pattern matching replaces String.trim_trailing(trimmed, ":")
    key = do_strip_trailing_colon(trimmed) |> unquote_key()

    case peek_next_indent(rest) do
      indent when indent > expected_indent ->
        nested_lines = take_nested_lines(rest, expected_indent)
        actual_indent = get_first_content_indent(nested_lines)

        {nested_value, _} =
          parse_object_lines(nested_lines, actual_indent, opts, %{
            quoted_keys: MapSet.new(),
            key_order: []
          })

        {remaining, _} = skip_nested_lines(rest, expected_indent)
        {%{key => nested_value}, remaining}

      _ ->
        {%{key => %{}}, rest}
    end
  end

  defp parse_array_from_header(trimmed, rest, expected_indent, opts, :tabular) do
    case Regex.run(@tabular_array_header_regex, trimmed) do
      [_, raw_key, array_marker, fields_str] ->
        key = unquote_key(raw_key)
        delimiter = extract_delimiter(array_marker)
        fields = parse_fields(fields_str, delimiter)
        # Use take_array_data_lines instead of take_nested_lines — tabular data rows
        # are NOT key-value fields, so we must stop at lines like "generated: 2024-03-15"
        data_rows = take_array_data_lines(rest, expected_indent, opts)
        array_data = parse_tabular_data_rows(data_rows, fields, delimiter, opts)
        {remaining, _} = skip_array_data_lines(rest, expected_indent)
        {%{key => array_data}, remaining}

      nil ->
        raise DecodeError, message: "Invalid tabular array header in list item", input: trimmed
    end
  end

  defp parse_array_from_header(trimmed, rest, expected_indent, opts, :list) do
    case Regex.run(@list_array_header_regex, trimmed) do
      [_, raw_key, array_marker] ->
        key = unquote_key(raw_key)
        delimiter = extract_delimiter(array_marker)
        opts_with_delimiter = Map.put(opts, :delimiter, delimiter)
        items = parse_list_array_items(rest, expected_indent, opts_with_delimiter)
        {remaining, _} = skip_nested_lines(rest, expected_indent)
        {%{key => items}, remaining}

      nil ->
        raise DecodeError, message: "Invalid list array header in list item", input: trimmed
    end
  end

  defp parse_list_item_with_array(trimmed, rest, _line, expected_indent, opts, array_type) do
    {result, remaining} =
      parse_array_from_header(trimmed, rest, expected_indent, opts, array_type)

    {result, remaining}
  end

  # Take lines for array data (until we hit a non-array line at same level or higher).
  # For tabular arrays: take lines at depth > base_indent that DON'T look like fields.
  # For list arrays: take all lines > base_indent (list items and their nested content).
  # Performance: Uses do_starts_with_dash? (binary pattern matching) instead of
  # String.starts_with?(String.trim_leading(content), "-").
  defp take_array_data_lines(lines, base_indent, opts) do
    first_content = Enum.find(lines, fn line -> not line.is_blank end)

    is_list_array =
      case first_content do
        %{content: content} -> do_starts_with_dash?(content)
        nil -> false
      end

    if is_list_array do
      list_item_indent =
        case first_content do
          %{indent: indent} -> indent
          nil -> base_indent + Map.get(opts, :indent_size, 2)
        end

      Enum.take_while(lines, fn line ->
        cond do
          line.is_blank -> true
          line.indent > list_item_indent -> true
          line.indent == list_item_indent -> do_starts_with_dash?(line.content)
          true -> false
        end
      end)
    else
      # Tabular array: take lines that don't look like "key: value" fields
      Enum.take_while(lines, fn line ->
        cond do
          line.is_blank -> true
          line.indent > base_indent -> not String.match?(line.content, @field_pattern)
          true -> false
        end
      end)
    end
  end

  # Skip array data lines — mirrors take_array_data_lines logic.
  defp skip_array_data_lines(lines, base_indent) do
    first_content = Enum.find(lines, fn line -> not line.is_blank end)

    is_list_array =
      case first_content do
        %{content: content} -> do_starts_with_dash?(content)
        nil -> false
      end

    remaining =
      if is_list_array do
        list_item_indent =
          case first_content do
            %{indent: indent} -> indent
            nil -> base_indent + 2
          end

        Enum.drop_while(lines, fn line ->
          cond do
            line.is_blank -> true
            line.indent > list_item_indent -> true
            line.indent == list_item_indent -> do_starts_with_dash?(line.content)
            true -> false
          end
        end)
      else
        Enum.drop_while(lines, fn line ->
          cond do
            line.is_blank -> true
            line.indent > base_indent -> not String.match?(line.content, @field_pattern)
            true -> false
          end
        end)
      end

    {remaining, length(lines) - length(remaining)}
  end

  # Parse inline array from a line like "[2]: a,b"
  defp parse_inline_array_from_line(trimmed, rest) do
    # Extract: [N], [N|], [N\t] format
    case Regex.run(@inline_array_header_regex, trimmed) do
      [_, array_marker, values_str] ->
        delimiter = extract_delimiter(array_marker)

        values =
          if values_str == "" do
            []
          else
            parse_delimited_values(values_str, delimiter)
          end

        {values, rest}

      nil ->
        # Malformed, return as string
        {trimmed, rest}
    end
  end

  # Parse nested list-format array within a list item (e.g., "- [1]:" with nested items)
  defp parse_nested_list_array(_trimmed, rest, _line, expected_indent, opts) do
    array_lines = take_nested_lines(rest, expected_indent)

    if Enum.empty?(array_lines) do
      {[], rest}
    else
      nested_indent = get_first_content_indent(array_lines)
      array_items = parse_list_items(array_lines, nested_indent, opts, [])
      {rest_after_array, _} = skip_nested_lines(rest, expected_indent)

      {array_items, rest_after_array}
    end
  end

  # Parse inline array item in list
  defp parse_inline_array_item(%{content: content}, rest, _expected_indent, _opts) do
    trimmed = remove_list_marker(content)

    # Use parse_inline_array_from_line directly since it handles [N]: format
    parse_inline_array_from_line(trimmed, rest)
  end

  # Parse fields from tabular header - use active delimiter per TOON spec Section 6
  # Performance: Binary scan for quote presence replaces String.contains?/2.
  # Fast path uses :binary.split/3 (BIF) instead of String.split/3.
  defp parse_fields(fields_str, delimiter) do
    if not do_contains_byte?(fields_str, ?") do
      # Simple identifiers - fast path with :binary.split (BIF, no String overhead)
      # Note: Enum.map is used instead of :lists.map because private function
      # captures (&do_trim_leading/1) are Elixir closures that :lists.map
      # cannot invoke correctly at the Erlang level.
      fields_str
      |> :binary.split(delimiter, [:global])
      |> Enum.map(&do_trim_leading/1)
      |> Enum.map(&do_trim_trailing/1)
    else
      # Quoted field names present - use full quote-aware splitting
      split_respecting_quotes(fields_str, delimiter)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&unquote_key/1)
    end
  end

  # Extract delimiter from array marker like [2], [2|], [2\t]
  # Performance: Binary pattern matching instead of String.contains?
  defp extract_delimiter(array_marker) do
    do_extract_delimiter(array_marker)
  end

  defp do_extract_delimiter(<<>>), do: @comma
  defp do_extract_delimiter(<<?|, _rest::binary>>), do: @pipe
  defp do_extract_delimiter(<<?\t, _rest::binary>>), do: @tab
  defp do_extract_delimiter(<<_byte, rest::binary>>), do: do_extract_delimiter(rest)

  # Parse delimited values from row
  # Performance: Trim during split instead of separate Enum.map pass
  defp parse_delimited_values(row_str, delimiter) do
    actual_delimiter = detect_delimiter(row_str, delimiter)
    split_and_parse_values(row_str, actual_delimiter)
  end

  # Performance: Split and parse in single pass, trimming during split.
  # Uses iodata accumulation with :lists.reverse + IO.iodata_to_binary for
  # efficient field construction — avoids per-char String operations.
  defp split_and_parse_values(str, delimiter) do
    do_split_parse(str, delimiter, [], false, [])
  end

  # End of input — parse the last accumulated field
  defp do_split_parse("", _delimiter, current, _in_quote, acc) do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> do_trim_leading()
      |> do_trim_trailing()

    :lists.reverse([parse_value(current_str) | acc])
  end

  # Escaped character — append both backslash and char as a binary slice
  defp do_split_parse(<<"\\", char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_parse(rest, delimiter, [<<char>>, "\\" | current], in_quote, acc)
  end

  # Quote toggle — append quote character
  defp do_split_parse(<<"\"", rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_parse(rest, delimiter, ["\"" | current], not in_quote, acc)
  end

  # Delimiter hit outside quotes — parse accumulated field and start new one
  defp do_split_parse(<<char, rest::binary>>, delimiter, current, false, acc)
       when <<char>> == delimiter do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> do_trim_leading()
      |> do_trim_trailing()

    do_split_parse(rest, delimiter, [], false, [parse_value(current_str) | acc])
  end

  # Regular character — append as single-byte binary
  defp do_split_parse(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_parse(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  # Extract the auto-detect logic so both places that call it stay readable:
  # Performance: Single-pass binary scan instead of 2x String.contains?
  defp detect_delimiter(row_str, @comma) do
    if do_has_tab_no_comma?(row_str), do: @tab, else: @comma
  end

  defp detect_delimiter(_row_str, delimiter), do: delimiter

  # Single-pass binary scan: returns true if string contains tab but no comma
  defp do_has_tab_no_comma?(<<>>), do: false
  defp do_has_tab_no_comma?(<<?\t, _rest::binary>>), do: true
  defp do_has_tab_no_comma?(<<?,, _rest::binary>>), do: false
  defp do_has_tab_no_comma?(<<_byte, rest::binary>>), do: do_has_tab_no_comma?(rest)

  # Split a string by delimiter, but don't split inside quoted strings
  defp split_respecting_quotes(str, delimiter) do
    # Use a simple state machine approach with iolist building for O(n) performance
    do_split_respecting_quotes(str, delimiter, [], false, [])
  end

  defp do_split_respecting_quotes("", _delimiter, current, _in_quote, acc) do
    # Reverse current iolist and convert to string, then reverse acc
    current_str = current |> :lists.reverse() |> IO.iodata_to_binary()
    :lists.reverse([current_str | acc])
  end

  defp do_split_respecting_quotes(<<"\\", char, rest::binary>>, delimiter, current, in_quote, acc) do
    # Escaped character - keep both backslash and char as iolist
    do_split_respecting_quotes(rest, delimiter, [<<char>>, "\\" | current], in_quote, acc)
  end

  defp do_split_respecting_quotes(<<"\"", rest::binary>>, delimiter, current, in_quote, acc) do
    # Toggle quote state - don't include the quote character in output
    do_split_respecting_quotes(rest, delimiter, current, not in_quote, acc)
  end

  # NOTE: delimiter must be a single ASCII byte (`,`, `\t`, or `|`).
  # Do not extend to multi-byte delimiters without replacing the byte-level
  # pattern match below.
  defp do_split_respecting_quotes(<<char, rest::binary>>, delimiter, current, false, acc)
       when <<char>> == delimiter do
    # Delimiter hit outside quotes — flush current field
    current_str = current |> :lists.reverse() |> IO.iodata_to_binary()
    do_split_respecting_quotes(rest, delimiter, [], false, [current_str | acc])
  end

  defp do_split_respecting_quotes(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    # Regular character or delimiter inside quotes
    do_split_respecting_quotes(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  defp parse_value(str) do
    # Fast-path: most tabular values are already clean (no leading/trailing whitespace)
    # Check first and last byte before doing any trimming work
    size = byte_size(str)

    cond do
      size == 0 ->
        do_parse_value("")

      :binary.first(str) in [?\s, ?\t] or :binary.last(str) in [?\s, ?\t] ->
        # Whitespace detected - do full trim
        str
        |> do_trim_leading()
        |> do_trim_trailing()
        |> do_parse_value()

      true ->
        # Already clean - parse directly
        do_parse_value(str)
    end
  end

  # Fast-path binary trimming - avoids String.trim overhead
  @compile {:inline, do_trim_leading: 1}
  defp do_trim_leading(<<?\s, rest::binary>>), do: do_trim_leading(rest)
  defp do_trim_leading(<<?\t, rest::binary>>), do: do_trim_leading(rest)
  defp do_trim_leading(str), do: str

  # Jason-style: binary scan for trailing whitespace instead of String.trim_trailing.
  # Uses :binary.last/1 (BIF, very fast) to check the last byte, and
  # binary_part/3 (O(1) sub-binary reference) to shrink the view.
  # For the common case (no trailing whitespace), this is a single BIF call + return.
  # For trailing whitespace, each iteration is O(1) — no intermediate allocations.
  @compile {:inline, do_trim_trailing: 1}
  defp do_trim_trailing(str), do: do_trim_trailing(str, byte_size(str))

  defp do_trim_trailing(_str, 0), do: <<>>

  defp do_trim_trailing(str, size) do
    case :binary.last(str) do
      byte when byte == ?\s or byte == ?\t ->
        do_trim_trailing(binary_part(str, 0, size - 1), size - 1)

      _ ->
        str
    end
  end

  defp do_parse_value("null"), do: nil
  defp do_parse_value("true"), do: true
  defp do_parse_value("false"), do: false
  defp do_parse_value("\"" <> _ = str), do: unquote_string(str)
  defp do_parse_value(str), do: parse_number_or_string(str)

  # Parse number or return as string
  # Per TOON spec: numbers with leading zeros (except "0" itself) are treated as strings

  # "0" and "-0" are valid numbers (both return 0)
  defp parse_number_or_string("0"), do: 0
  defp parse_number_or_string("-0"), do: 0

  # Leading zeros make it a string (e.g., "05", "-007")
  defp parse_number_or_string(<<"0", d, _rest::binary>> = str) when d in ?0..?9, do: str
  defp parse_number_or_string(<<"-0", d, _rest::binary>> = str) when d in ?0..?9, do: str

  # Try to parse as number, fall back to string
  defp parse_number_or_string(str) do
    case Float.parse(str) do
      {num, ""} -> normalize_parsed_number(num, str)
      _ -> str
    end
  end

  # Convert parsed float to appropriate type based on original string format
  defp normalize_parsed_number(num, str) do
    if has_decimal_or_exponent?(str) do
      normalize_decimal_number(num)
    else
      String.to_integer(str)
    end
  end

  # Performance: Single-pass binary scan instead of 3x String.contains?
  defp has_decimal_or_exponent?(<<>>), do: false
  defp has_decimal_or_exponent?(<<?., _rest::binary>>), do: true
  defp has_decimal_or_exponent?(<<?e, _rest::binary>>), do: true
  defp has_decimal_or_exponent?(<<?E, _rest::binary>>), do: true
  defp has_decimal_or_exponent?(<<_byte, rest::binary>>), do: has_decimal_or_exponent?(rest)

  defp normalize_decimal_number(num) when num == trunc(num), do: trunc(num)
  defp normalize_decimal_number(num), do: num

  # Remove quotes from key
  # Jason-style: binary pattern matching instead of String.slice
  # Strips surrounding quotes in O(1) via binary_part — no allocation.
  defp unquote_key(<<"\"", rest::binary>>) do
    case do_strip_trailing_quote(rest) do
      {:ok, inner} ->
        unescape_string(inner)

      :error ->
        raise DecodeError, message: "Unterminated quoted key", input: <<"\"", rest::binary>>
    end
  end

  defp unquote_key(key), do: key

  # Strip trailing quote from a binary, returning {:ok, inner} or :error.
  defp do_strip_trailing_quote(<<>>), do: :error
  defp do_strip_trailing_quote(<<"\\">>), do: :error
  defp do_strip_trailing_quote(<<"\"", _::binary>>), do: :error

  defp do_strip_trailing_quote(binary) do
    size = byte_size(binary)
    <<last>> = binary_part(binary, size - 1, 1)

    if last == ?" do
      {:ok, binary_part(binary, 0, size - 1)}
    else
      :error
    end
  end

  # Check if a key was originally quoted in the source line.
  # Jason-style: binary pattern matching instead of String.trim_leading + String.starts_with?
  # Eliminates 2 intermediate allocations.
  @compile {:inline, key_was_quoted?: 1}
  defp key_was_quoted?(<<"\"", _rest::binary>>), do: true
  defp key_was_quoted?(<<?\s, rest::binary>>), do: key_was_quoted?(rest)
  defp key_was_quoted?(<<?\t, rest::binary>>), do: key_was_quoted?(rest)
  defp key_was_quoted?(_), do: false

  # Update metadata with a key, checking if it was quoted
  @compile {:inline, add_key_to_metadata: 3}
  defp add_key_to_metadata(key, was_quoted, metadata) do
    updated =
      if was_quoted,
        do: %{metadata | quoted_keys: MapSet.put(metadata.quoted_keys, key)},
        else: metadata

    %{updated | key_order: [key | updated.key_order]}
  end

  # Unquote a string value (remove surrounding quotes and unescape)
  defp unquote_string(<<"\"", rest::binary>>) do
    case do_ends_with_unescaped_quote?(rest) do
      true ->
        # Strip the trailing quote via binary_part (O(1) sub-binary)
        inner = binary_part(rest, 0, byte_size(rest) - 1)
        unescape_string(inner)

      false ->
        raise DecodeError, message: "Unterminated quoted string", input: <<"\"", rest::binary>>
    end
  end

  defp unquote_string(str), do: str

  # Check if binary ends with an unescaped quote character.
  # Performance: Binary scan from end — O(n) worst case but typically O(1)
  # since most strings don't end with backslashes.
  defp do_ends_with_unescaped_quote?(<<>>), do: false
  defp do_ends_with_unescaped_quote?(<<"\\">>), do: false

  defp do_ends_with_unescaped_quote?(binary) do
    size = byte_size(binary)
    <<last>> = binary_part(binary, size - 1, 1)

    if last == ?" do
      # Check if the quote is escaped by counting preceding backslashes
      not escaped_quote_at_end?(binary)
    else
      false
    end
  end

  # Check if the quote at the end of the string is escaped.
  # An escaped quote is preceded by an odd number of backslashes.
  defp escaped_quote_at_end?(binary) do
    count = do_count_trailing_backslashes(binary)
    rem(count, 2) == 1
  end

  # Count trailing backslashes in a binary.
  # Performance: Scans from end using binary_part — avoids creating reversed copy.
  defp do_count_trailing_backslashes(<<>>), do: 0
  defp do_count_trailing_backslashes(<<last>>), do: if(last == ?\\, do: 1, else: 0)

  defp do_count_trailing_backslashes(<<last, _rest::binary>>) when last != ?\\,
    do: 0

  defp do_count_trailing_backslashes(binary) do
    do_count_backslashes_from_end(binary, byte_size(binary), 0)
  end

  defp do_count_backslashes_from_end(_binary, 0, count), do: count

  defp do_count_backslashes_from_end(binary, pos, count) do
    <<byte>> = binary_part(binary, pos - 1, 1)

    if byte == ?\\ do
      do_count_backslashes_from_end(binary, pos - 1, count + 1)
    else
      count
    end
  end

  # Jason-style zero-copy unescape: scan the original binary once, building
  # an iodata list of binary_part slices (O(1) sub-binary references) and
  # escape replacement strings. Only the escape replacement sequences are newly
  # allocated. For strings with few escapes (the common case), this dramatically
  # reduces the number of list elements and avoids per-byte allocation.
  defp unescape_string(str), do: do_unescape(str, str, 0, [])

  # Main loop: scan for backslash or end of input
  defp do_unescape(<<>>, original, skip, acc),
    do: finalize_unescape(acc, original, skip, 0)

  defp do_unescape(<<"\\">>, _original, _skip, _acc),
    do: raise(DecodeError, message: "Unterminated escape sequence", input: "\\")

  defp do_unescape(<<"\\", char, rest::binary>>, original, skip, acc) do
    # Flush any accumulated safe chunk, then append escape replacement
    acc = flush_unescape_chunk(acc, original, skip, 0)
    replacement = escape_char(char)
    do_unescape(rest, original, skip + 2, [replacement | acc])
  end

  # Safe byte — enter chunk accumulation mode
  defp do_unescape(<<_byte, rest::binary>>, original, skip, acc),
    do: do_unescape_chunk(rest, original, skip, 1, acc)

  # Chunk accumulation: count consecutive safe bytes without allocating
  defp do_unescape_chunk(<<>>, original, skip, len, acc),
    do: finalize_unescape([binary_part(original, skip, len) | acc], original, skip, 0)

  defp do_unescape_chunk(<<"\\">>, _original, _skip, _len, _acc),
    do: raise(DecodeError, message: "Unterminated escape sequence", input: "\\")

  defp do_unescape_chunk(<<"\\", char, rest::binary>>, original, skip, len, acc) do
    # Flush chunk via binary_part (O(1)), then append escape replacement
    part = binary_part(original, skip, len)
    replacement = escape_char(char)
    do_unescape(rest, original, skip + len + 2, [replacement, part | acc])
  end

  defp do_unescape_chunk(<<_byte, rest::binary>>, original, skip, len, acc),
    do: do_unescape_chunk(rest, original, skip, len + 1, acc)

  # Flush a zero-length chunk (no-op) — avoids unnecessary binary_part call
  @compile {:inline, flush_unescape_chunk: 4}
  defp flush_unescape_chunk(acc, _original, _skip, 0), do: acc

  defp flush_unescape_chunk(acc, original, skip, len),
    do: [binary_part(original, skip, len) | acc]

  # Final assembly: reverse the iodata list and convert to binary
  @compile {:inline, finalize_unescape: 4}
  defp finalize_unescape(acc, _original, _skip, 0),
    do: acc |> :lists.reverse() |> IO.iodata_to_binary()

  defp finalize_unescape(acc, original, skip, len),
    do: [binary_part(original, skip, len) | acc] |> :lists.reverse() |> IO.iodata_to_binary()

  # Escape character lookup — inlined for zero-overhead dispatch
  defp escape_char(?\\), do: "\\"
  defp escape_char(?"), do: "\""
  defp escape_char(?n), do: "\n"
  defp escape_char(?r), do: "\r"
  defp escape_char(?t), do: "\t"

  defp escape_char(char),
    do:
      raise(DecodeError, message: "Invalid escape sequence: \\#{<<char>>}", input: <<?\\, char>>)

  # Peek at next line's indent (skip blank lines)
  # Note: get_first_content_indent/1 shares the same logic but is kept separate
  # for semantic clarity - both are inlined for performance
  defp peek_next_indent([]), do: 0
  defp peek_next_indent([%{is_blank: true} | rest]), do: peek_next_indent(rest)
  defp peek_next_indent([%{indent: indent} | _]), do: indent

  # Get the indent of the first non-blank line
  defp get_first_content_indent([]), do: 0
  defp get_first_content_indent([%{is_blank: true} | rest]), do: get_first_content_indent(rest)
  defp get_first_content_indent([%{indent: indent} | _]), do: indent

  # Take lines that are more indented than base
  defp take_nested_lines(lines, base_indent) do
    # We need to handle blank lines carefully:
    # - Blank lines BETWEEN nested content should be included
    # - Blank lines AFTER nested content should NOT be included
    # We'll use a helper that tracks whether we're still in nested content
    take_nested_lines_helper(lines, base_indent, false)
  end

  # Performance: Struct pattern matching in function heads replaces cond + map access.
  # Non-blank lines with indent > base_indent are the common "include" case.

  defp take_nested_lines_helper([], _base_indent, _seen_content), do: []

  # Non-blank line that's more indented: include it and continue
  defp take_nested_lines_helper(
         [%{is_blank: false, indent: indent} = line | rest],
         base_indent,
         _seen_content
       )
       when indent > base_indent do
    [line | take_nested_lines_helper(rest, base_indent, true)]
  end

  # Non-blank line at base level or less: stop here
  defp take_nested_lines_helper([%{is_blank: false} | _], _base_indent, _seen_content), do: []

  # Blank line: only include if the next non-blank line is still nested
  defp take_nested_lines_helper([%{is_blank: true} = line | rest], base_indent, seen_content) do
    next_content_indent = peek_next_indent(rest)

    if next_content_indent > base_indent do
      [line | take_nested_lines_helper(rest, base_indent, seen_content)]
    else
      # Next content is at base level or less, so stop here
      []
    end
  end

  # Fixed – mirrors the logic of take_nested_lines_helper
  defp skip_nested_lines(lines, base_indent) do
    remaining = do_skip_nested(lines, base_indent)
    {remaining, length(lines) - length(remaining)}
  end

  # Performance: Struct pattern matching in function heads replaces cond + map access.

  defp do_skip_nested([], _base_indent), do: []

  # Non-blank line that's more indented: skip it and continue
  defp do_skip_nested([%{is_blank: false, indent: indent} | rest], base_indent)
       when indent > base_indent do
    do_skip_nested(rest, base_indent)
  end

  # Non-blank line at base level or less: stop here
  defp do_skip_nested([%{is_blank: false} | _] = all, _base_indent), do: all

  # Blank line: only skip if the next non-blank line is still nested
  defp do_skip_nested([%{is_blank: true} | rest] = all, base_indent) do
    if peek_next_indent(rest) > base_indent do
      do_skip_nested(rest, base_indent)
    else
      all
    end
  end

  # Take lines for a list item (until next item marker at same level)
  defp take_item_lines(lines, base_indent) do
    Enum.take_while(lines, fn line ->
      # Take lines that are MORE indented than base (continuation lines)
      # Stop at next list item marker at the same level
      if line.indent == base_indent do
        not do_starts_with_dash?(line.content)
      else
        line.indent > base_indent
      end
    end)
  end
end
