defmodule Toon.Decode.StructuralParser do
  @moduledoc """
  Structural parser for TOON format that handles indentation-based nesting.

  This parser processes TOON input by analyzing indentation levels and building
  a hierarchical structure from the flat text representation.
  """

  alias Toon.Decode.Parser
  alias Toon.DecodeError

  @invalid_escape_pattern ~r/\\/

  # Module-level regex patterns for structural matching
  @tabular_header_pattern ~r/^(?:"[^"]*"|[\w.]+)\[\d+.*\]\{[^}]+\}:$/
  @list_header_pattern ~r/^(?:"[^"]*"|[\w.]+)\[\d+.*\]:$/
  @inline_array_pattern ~r/^\[.*?\]: .+/
  @list_array_header_pattern ~r/^\[\d+[^\]]*\]:$/
  @field_pattern ~r/^[\w"]+\s*:/
  @tabular_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+.*\])\{([^}]+)\}:$/
  @list_array_regex ~r/^((?:"[^"]*"|[\w.]+))\[(\d+).*\]:$/

  @type line_info :: %{
          content: String.t(),
          indent: non_neg_integer(),
          line_number: non_neg_integer(),
          original: String.t()
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

    # Validate indentation in strict mode
    if opts.strict do
      validate_indentation(lines, opts)
    end

    # Initialize metadata accumulator
    initial_metadata = %{
      quoted_keys: MapSet.new(),
      key_order: []
    }

    {result, metadata} =
      case lines do
        [] ->
          {%{}, initial_metadata}

        _ ->
          parse_structure(lines, 0, opts, initial_metadata)
      end

    {:ok, {result, metadata}}
  rescue
    e in DecodeError ->
      {:error, e}

    e ->
      {:error,
       DecodeError.exception(
         message: "Parse failed: #{Exception.message(e)}",
         input: input
       )}
  end

  # Preprocess input into line information structures
  defp preprocess_lines(input) do
    input
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_num} ->
      %{
        content: String.trim_leading(line),
        indent: calculate_indent(line),
        line_number: line_num,
        original: line,
        is_blank: String.trim(line) == ""
      }
    end)
    # Filter out blank lines at the end
    |> Enum.reverse()
    |> Enum.drop_while(& &1.is_blank)
    |> Enum.reverse()
  end

  # Calculate indentation level (number of leading spaces)
  defp calculate_indent(line) do
    line
    |> String.to_charlist()
    |> Enum.take_while(&(&1 == ?\s))
    |> length()
  end

  # Validate indentation in strict mode
  defp validate_indentation(lines, opts) do
    Enum.each(lines, fn line ->
      # Skip blank lines
      unless line.is_blank do
        # Check for tab characters in INDENTATION only (not in content after the key/value starts)
        # We need to check the leading whitespace before any content
        # Find where content starts (first non-whitespace character)
        leading_whitespace =
          line.original
          |> String.to_charlist()
          |> Enum.take_while(&(&1 == ?\s or &1 == ?\t))
          |> List.to_string()

        if String.contains?(leading_whitespace, "\t") do
          raise DecodeError,
            message: "Tab characters are not allowed in indentation (strict mode)",
            input: line.original
        end

        # Check if indent is a multiple of indent_size
        if line.indent > 0 and rem(line.indent, opts.indent_size) != 0 do
          raise DecodeError,
            message: "Indentation must be a multiple of #{opts.indent_size} spaces (strict mode)",
            input: line.original
        end
      end
    end)
  end

  # Parse a structure starting from given lines at a specific indent level
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
  defp detect_root_type([%{content: content} | rest]) do
    cond do
      # Root array header patterns
      String.starts_with?(content, "[") ->
        {:root_array, :inline}

      String.match?(content, ~r/^\[.*\]\{.*\}:/) ->
        {:root_array, :tabular}

      String.match?(content, ~r/^\[.*\]:/) ->
        {:root_array, :list}

      # Single line -> check if it's a primitive or key-value
      rest == [] ->
        # Check if it looks like a key-value pair by pattern matching
        # Match: <key>: <value> or <key>: (empty) where key can include array markers like [N]
        # Pattern: (quoted_key|unquoted_key)(optional_array_marker): (space or end of line)
        # Quoted keys can contain escaped quotes: "(?:[^"\\]|\\.)*"
        # Unquoted keys can include: letters, numbers, _, -, .
        if String.match?(content, ~r/^(?:"(?:[^"\\]|\\.)*"|[\w.-]+)(?:\[[^\]]*\])?:(?:\s|$)/) do
          # It's a key-value pair -> object
          {:object, nil}
        else
          # Not a valid key-value pair -> treat as root primitive
          {:root_primitive, nil}
        end

      true ->
        {:object, nil}
    end
  end

  # Parse root primitive value (single value without key)
  defp parse_root_primitive([%{content: content}], _opts, metadata) do
    # For root primitives, we parse directly without parser combinator
    # This handles quoted strings with escapes correctly
    {parse_value(content), metadata}
  end

  # Parse root-level array
  defp parse_root_array([%{content: header_line} = line_info | rest], opts, metadata) do

    case Parser.parse_line(header_line) do
      {:ok, [result], "", _, _, _} ->
        # Handle inline array
        case result do
          {key, value} when is_list(value) ->
            # Track metadata from parsed key-value
            was_quoted = key_was_quoted?(header_line)
            updated_metadata = add_key_to_metadata(key, was_quoted, metadata)
            {value, updated_metadata}

          _ ->
            raise DecodeError, message: "Invalid root array format", input: header_line
        end

      {:error, _reason, _, _, _, _} ->
        # Try parsing as tabular or list format
        parse_complex_root_array(line_info, rest, opts, metadata)
    end
  end

  defp parse_complex_root_array(%{content: header}, rest, opts, metadata) do
    cond do
      # Inline array with delimiter marker: [3\t]: ... or [3|]: ... or [3]: ...
      String.match?(header, ~r/^\[\d+[^\]]*\]: /) ->
        {parse_root_inline_array(header, opts), metadata}

      # Tabular array: [N]{fields}:
      String.match?(header, ~r/^\[\d+[^\]]*\]\{[^}]+\}:$/) ->
        {parse_tabular_array_data(header, rest, 0, opts), metadata}

      # List array: [N]:
      String.match?(header, ~r/^\[\d+[^\]]*\]:$/) ->
        {parse_list_array_items(rest, 0, opts), metadata}

      true ->
        raise DecodeError, message: "Invalid root array header", input: header
    end
  end

  # Parse root inline array from header line
  defp parse_root_inline_array(header, _opts) do
    # Extract everything after ": "
    case String.split(header, ": ", parts: 2) do
      [array_marker, values_str] ->
        # Extract declared length from [N]
        declared_length =
          case Regex.run(~r/\[(\d+)/, array_marker) do
            [_, length_str] -> String.to_integer(length_str)
            _ -> nil
          end

        delimiter = extract_delimiter(array_marker)
        values = parse_delimited_values(values_str, delimiter)

        # Validate length if declared
        if declared_length != nil and length(values) != declared_length do
          raise DecodeError,
            message: "Array length mismatch: declared #{declared_length}, got #{length(values)}",
            input: header
        end

        values

      _ ->
        raise DecodeError, message: "Invalid root inline array", input: header
    end
  end

  # Helper function to build map with appropriate key type
  defp build_map_with_keys(entries, opts) do
    case opts.keys do
      :strings -> Map.new(entries)
      :atoms -> Map.new(entries, fn {k, v} -> {String.to_atom(k), v} end)
      :atoms! -> Map.new(entries, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end
  end

  defp put_key(map, key, value, opts) do
    case opts.keys do
      :strings -> Map.put(map, key, value)
      :atoms -> Map.put(map, String.to_atom(key), value)
      :atoms! -> Map.put(map, String.to_existing_atom(key), value)
    end
  end

  defp empty_map(_opts), do: %{}

  # Parse object from lines
  defp parse_object_lines(lines, base_indent, opts, metadata) do
    {entries, _remaining, updated_metadata} = parse_entries(lines, base_indent, opts, metadata)
    {build_map_with_keys(entries, opts), updated_metadata}
  end

  # Parse entries at a specific indentation level
  defp parse_entries([], _base_indent, _opts, metadata), do: {[], [], metadata}

  defp parse_entries([line | rest] = lines, base_indent, opts, metadata) do

    cond do
      # Skip blank lines (only at root level or when not strict)
      line.is_blank ->
        # When strict, blank lines in nested content should be rejected by take_nested_lines
        parse_entries(rest, base_indent, opts, metadata)

      # Skip lines that are less indented (parent level)
      line.indent < base_indent ->
        {[], lines, metadata}

      # Skip lines that are more indented (will be handled by parent)
      line.indent > base_indent ->
        {[], lines, metadata}

      # Process line at current level
      true ->
        case parse_entry_line(line, rest, base_indent, opts, metadata) do
          {:entry, key, value, remaining, updated_metadata} ->


            {entries, final_remaining, final_metadata} =
              parse_entries(remaining, base_indent, opts, updated_metadata)

            {[{key, value} | entries], final_remaining, final_metadata}

          {:skip, remaining, updated_metadata} ->

            parse_entries(remaining, base_indent, opts, updated_metadata)
        end
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
                case Regex.run(~r/^[\w"]+(\[(\d+)[^\]]*\]):/, content) do
                  [_, array_marker, length_str] ->
                    declared_length = String.to_integer(length_str)
                    delimiter = extract_delimiter(array_marker)
                    # Re-parse the values with correct delimiter
                    case String.split(content, ": ", parts: 2) do
                      [_, values_str] ->
                        values = parse_delimited_values(values_str, delimiter)

                        # Validate length
                        if length(values) != declared_length do
                          raise DecodeError,
                            message:
                              "Array length mismatch: declared #{declared_length}, got #{length(values)}",
                            input: content
                        end

                        values

                      _ ->
                        value
                    end

                  _ ->
                    value
                end

              {:entry, key, corrected_value, rest, updated_meta}
            end

          {key, value} when is_map(value) ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)
            # Simple value, not nested
            {:entry, key, value, rest, updated_meta}

          {key, value} ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            # Check if next lines are nested
            case peek_next_indent(rest) do
              indent when indent > base_indent ->
                # Has nested content
                {nested_value, nested_meta} =
                  parse_nested_value(key, rest, base_indent, opts, updated_meta)

                {remaining_lines, _} = skip_nested_lines(rest, base_indent)
                {:entry, key, nested_value, remaining_lines, nested_meta}

              _ ->
                # Simple primitive value - re-parse the entire value to respect special cases
                # This handles: leading zeros, commas in strings, etc.
                corrected_value =
                  case String.split(content, ": ", parts: 2) do
                    [_, value_str] ->
                      # Re-parse the entire value string
                      parse_value(String.trim(value_str))

                    _ ->
                      value
                  end

                {:entry, key, corrected_value, rest, updated_meta}
            end
        end

      {:ok, [parsed_result], rest_content, _, _, _} when rest_content != "" ->
        # Parser didn't consume the entire line - re-parse the value manually
        # This handles cases like "note: a,b" where the parser stops at the comma
        case parsed_result do
          {key, _partial_value} ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            # Re-extract the full value from the original content
            case String.split(content, ": ", parts: 2) do
              [_, value_str] ->
                full_value = parse_value(String.trim(value_str))
                {:entry, key, full_value, rest, updated_meta}

              _ ->
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

  # Pattern matching helpers for handle_special_line
  defp tabular_array_header?(content), do: String.match?(content, @tabular_header_pattern)
  defp list_array_header?(content), do: String.match?(content, @list_header_pattern)

  defp nested_object_header?(content) do
    String.ends_with?(content, ":") and not String.contains?(content, " ")
  end

  # Handle special line formats (array headers, etc.)
  defp handle_special_line(%{content: content} = line_info, rest, base_indent, opts, metadata) do
    cond do
      tabular_array_header?(content) ->
        parse_tabular_array_entry(line_info, rest, base_indent, opts, metadata)

      list_array_header?(content) ->
        parse_list_array_entry(line_info, rest, base_indent, opts, metadata)

      nested_object_header?(content) ->
        parse_nested_object_entry(content, rest, base_indent, opts, metadata)

      true ->
        {:skip, rest, metadata}
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

  defp parse_nested_object_entry(content, rest, base_indent, opts, metadata) do
    key = content |> String.trim_trailing(":") |> unquote_key()
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
    # Extract key and fields from header (with optional # length marker and quoted key)
    case Regex.run(~r/^((?:"[^"]*"|[\w.]+))(\[\d+.*\])\{([^}]+)\}:$/, header) do
      [_, raw_key, array_marker, fields_str] ->
        key = unquote_key(raw_key)
        was_quoted = key_was_quoted?(header)
        updated_meta = add_key_to_metadata(key, was_quoted, metadata)

        delimiter = extract_delimiter(array_marker)
        fields = parse_fields(fields_str, delimiter)

        # Get data rows
        data_rows = take_nested_lines(rest, base_indent)
        array_data = parse_tabular_data_rows(data_rows, fields, delimiter, opts)

        {{key, array_data}, updated_meta}

      nil ->
        raise DecodeError, message: "Invalid tabular array header", input: header
    end
  end

  # Parse tabular array data rows
  defp parse_tabular_data_rows(lines, fields, delimiter, opts) do
    # Filter out blank lines (validate in strict mode)
    non_blank_lines =
      Enum.reject(lines, fn line ->
        if line.is_blank do
          if opts.strict do
            raise DecodeError,
              message: "Blank lines are not allowed inside arrays in strict mode",
              input: line.original
          end

          true
        else
          false
        end
      end)

    Enum.map(non_blank_lines, fn %{content: row_content} ->
      values = parse_delimited_values(row_content, delimiter)

      if length(values) != length(fields) do
        raise DecodeError,
          message: "Row value count mismatch: expected #{length(fields)}, got #{length(values)}",
          input: row_content
      end

      # Build object from fields and values using helper
      entries = Enum.zip(fields, values)
      build_map_with_keys(entries, opts)
    end)
  end

  # Parse tabular array data (for root arrays)
  defp parse_tabular_array_data(header, rest, base_indent, opts) do
    case Regex.run(~r/^\[((\d+))([^\]]*)\]\{([^}]+)\}:$/, header) do
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
    case Regex.run(~r/^((?:"[^"]*"|[\w.]+))(\[\d+[^\]]*\]):$/, header) do
      [_, raw_key, array_marker] ->
        length_str =
          case Regex.run(~r/\[(\d+)/, array_marker) do
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

        # Validate length
        if length(items) != declared_length do
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

  # Parse individual list items
  defp parse_list_items([], _expected_indent, _opts, acc), do: Enum.reverse(acc)

  defp parse_list_items([line | rest], expected_indent, opts, acc) do
    cond do
      # Skip blank lines (validate in strict mode if within array content)
      line.is_blank ->
        if opts.strict do
          raise DecodeError,
            message: "Blank lines are not allowed inside arrays in strict mode",
            input: line.original
        else
          parse_list_items(rest, expected_indent, opts, acc)
        end

      # Inline array item with values on same line: - [N]: val1,val2
      # (must have content after ": ", otherwise it's a list-format array header)
      String.match?(line.content, ~r/^\s*- \[.*\]: .+/) ->
        {item, remaining} = parse_inline_array_item(line, rest, expected_indent, opts)
        parse_list_items(remaining, expected_indent, opts, [item | acc])

      # List item marker (with space "- " or just "-")
      String.starts_with?(String.trim_leading(line.content), "-") ->
        {item, remaining} = parse_list_item(line, rest, expected_indent, opts)
        parse_list_items(remaining, expected_indent, opts, [item | acc])

      true ->
        parse_list_items(rest, expected_indent, opts, acc)
    end
  end

  # Pattern matching helpers for list item parsing
  defp remove_list_marker(content) do
    content
    |> String.trim_leading()
    |> String.replace_prefix("- ", "")
    |> String.replace_prefix("-", "")
  end

  defp inline_array_with_values?(str), do: String.match?(str, @inline_array_pattern)
  defp list_array_header_only?(str), do: String.match?(str, @list_array_header_pattern)

  # Parse a single list item
  defp parse_list_item(%{content: content} = line, rest, expected_indent, opts) do
    trimmed = remove_list_marker(content)
    route_list_item(trimmed, rest, line, expected_indent, opts)
  end

  defp route_list_item("", rest, _line, _expected_indent, _opts), do: {%{}, rest}

  defp route_list_item(trimmed, rest, line, expected_indent, opts) do
    trimmed_stripped = String.trim(trimmed)

    cond do
      trimmed_stripped == "" ->
        {%{}, rest}

      inline_array_with_values?(trimmed) ->
        parse_inline_array_from_line(trimmed, rest)

      list_array_header_only?(trimmed) ->
        parse_nested_list_array(trimmed, rest, line, expected_indent, opts)

      tabular_array_header?(trimmed) ->
        parse_list_item_with_array(trimmed, rest, line, expected_indent, opts, :tabular)

      list_array_header?(trimmed) ->
        parse_list_item_with_array(trimmed, rest, line, expected_indent, opts, :list)

      true ->
        parse_list_item_normal(trimmed, rest, line, expected_indent, opts)
    end
  end

  # Normal list item parsing (extracted to helper)
  defp parse_list_item_normal(trimmed, rest, line, expected_indent, opts) do
    delimiter = Map.get(opts, :delimiter, ",")

    case Parser.parse_line(trimmed) do
      {:ok, [result], "", _, _, _} ->
        handle_complete_parse(result, trimmed, rest, line, expected_indent, opts)

      {:ok, [{key, partial_value}], remaining_input, _, _, _}
      when is_binary(remaining_input) and remaining_input != "" ->
        handle_partial_parse(
          key,
          partial_value,
          remaining_input,
          delimiter,
          rest,
          line,
          expected_indent,
          opts
        )

      {:error, _, _, _, _, _} ->
        handle_parse_error(trimmed, rest, expected_indent, opts)
    end
  end

  # Handle case when parser fully consumed input
  defp handle_complete_parse(result, trimmed, rest, line, expected_indent, opts) do
    case result do
      {_key, _value} ->
        # Object item - collect all fields including continuation lines
        continuation_lines = take_item_lines(rest, expected_indent)

        item_indent =
          if length(continuation_lines) > 0 do
            continuation_lines |> Enum.map(& &1.indent) |> Enum.min()
          else
            line.indent
          end

        item_lines = [%{line | content: trimmed, indent: item_indent} | continuation_lines]
        # List items don't need metadata tracking (not top-level)
        empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
        {object, _} = parse_object_lines(item_lines, item_indent, opts, empty_metadata)
        remaining = Enum.drop(rest, length(continuation_lines))
        {object, remaining}

      value ->
        # Primitive item
        {value, rest}
    end
  end

  # Handle case when parser has remaining input
  defp handle_partial_parse(
         key,
         partial_value,
         remaining_input,
         delimiter,
         rest,
         line,
         expected_indent,
         opts
       ) do
    # If delimiter is NOT comma but remaining starts with comma, the value has commas
    if delimiter != "," and String.starts_with?(remaining_input, ",") do
      # Re-parse: the full value is partial_value + remaining_input
      full_value = parse_value(to_string(partial_value) <> remaining_input)

      continuation_lines = take_item_lines(rest, expected_indent)

      item_indent =
        if length(continuation_lines) > 0 do
          continuation_lines |> Enum.map(& &1.indent) |> Enum.min()
        else
          line.indent
        end

      adjusted_content = "#{key}: #{full_value}"
      item_lines = [%{line | content: adjusted_content, indent: item_indent} | continuation_lines]
      # List items don't need metadata tracking (not top-level)
      empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
      {object, _} = parse_object_lines(item_lines, item_indent, opts, empty_metadata)
      remaining = Enum.drop(rest, length(continuation_lines))
      {object, remaining}
    else
      raise DecodeError,
        message: "Parse failed: unexpected remaining input '#{remaining_input}'",
        reason: :parse_error
    end
  end

  # Handle case when parser failed
  defp handle_parse_error(trimmed, rest, expected_indent, opts) do
    # Check if this is a key-only line (e.g., "data:") with nested content
    if String.ends_with?(trimmed, ":") and not String.contains?(trimmed, " ") do
      next_indent = peek_next_indent(rest)

      if next_indent > expected_indent do
        parse_nested_key_with_content(trimmed, rest, next_indent, expected_indent, opts)
      else
        # No nested content, treat as primitive value
        {parse_value(trimmed), rest}
      end
    else
      # Primitive value without key - parse as standalone value
      {parse_value(trimmed), rest}
    end
  end

  # Helper to drop lines at a certain level
  defp drop_lines_at_level(lines, min_indent) do
    Enum.drop_while(lines, fn line -> !line.is_blank and line.indent >= min_indent end)
  end

  # Helper to build object with nested value
  defp build_object_with_nested(key, nested_value, [], opts) do
    put_key(empty_map(opts), key, nested_value, opts)
  end

  defp build_object_with_nested(key, nested_value, more_fields, opts) do
    field_indent = more_fields |> Enum.map(& &1.indent) |> Enum.min()
    empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
    {remaining_object, _} = parse_object_lines(more_fields, field_indent, opts, empty_metadata)
    put_key(remaining_object, key, nested_value, opts)
  end

  # Parse a key with nested content
  defp parse_nested_key_with_content(trimmed, rest, next_indent, expected_indent, opts) do
    key = trimmed |> String.trim_trailing(":") |> unquote_key()

    # Take lines at the nested level
    nested_lines = take_lines_at_level(rest, next_indent)
    empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
    {nested_value, _} = parse_object_lines(nested_lines, next_indent, opts, empty_metadata)

    # Skip consumed nested lines
    remaining_after_nested = drop_lines_at_level(rest, next_indent)

    # Take remaining fields at the same level
    more_fields = take_item_lines(remaining_after_nested, expected_indent)

    object = build_object_with_nested(key, nested_value, more_fields, opts)

    final_remaining =
      if more_fields == [],
        do: remaining_after_nested,
        else: Enum.drop(remaining_after_nested, length(more_fields))

    {object, final_remaining}
  end

  # Helper to get nested indent for list arrays
  defp get_nested_indent([], expected_indent, opts),
    do: expected_indent + Map.get(opts, :indent_size, 2)

  defp get_nested_indent(lines, _expected_indent, _opts),
    do: lines |> Enum.map(& &1.indent) |> Enum.min()

  # Helper to parse remaining fields in list item
  defp parse_remaining_fields([], _opts), do: empty_map(nil)

  defp parse_remaining_fields(fields, opts) do
    field_indent = fields |> Enum.map(& &1.indent) |> Enum.min()
    empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
    {result, _} = parse_object_lines(fields, field_indent, opts, empty_metadata)
    result
  end

  # Parse array from tabular header
  defp parse_array_from_header(trimmed, rest, expected_indent, opts, :tabular) do
    case Regex.run(@tabular_header_regex, trimmed) do
      [_, raw_key, array_marker, fields_str] ->
        key = unquote_key(raw_key)
        delimiter = extract_delimiter(array_marker)
        fields = parse_fields(fields_str, delimiter)
        array_lines = take_array_data_lines(rest, expected_indent, opts)
        {key, parse_tabular_data_rows(array_lines, fields, delimiter, opts)}

      nil ->
        raise DecodeError, message: "Invalid tabular array in list item", input: trimmed
    end
  end

  # Parse array from list header
  defp parse_array_from_header(trimmed, rest, expected_indent, opts, :list) do
    case Regex.run(@list_array_regex, trimmed) do
      [_, raw_key, _length_str] ->
        key = unquote_key(raw_key)
        array_lines = take_array_data_lines(rest, expected_indent, opts)
        nested_indent = get_nested_indent(array_lines, expected_indent, opts)
        {key, parse_list_items(array_lines, nested_indent, opts, [])}

      nil ->
        raise DecodeError, message: "Invalid list array in list item", input: trimmed
    end
  end

  # Parse list item that starts with an array (tabular or list format)
  defp parse_list_item_with_array(trimmed, rest, _line, expected_indent, opts, array_type) do
    {key, array_value} = parse_array_from_header(trimmed, rest, expected_indent, opts, array_type)
    {rest_after_array, _} = skip_array_data_lines(rest, expected_indent)
    remaining_fields = take_item_lines(rest_after_array, expected_indent)

    remaining_object = parse_remaining_fields(remaining_fields, opts)
    object = put_key(remaining_object, key, array_value, opts)

    {remaining, _} = skip_item_lines(rest, expected_indent)
    {object, remaining}
  end

  # Take lines for array data (until we hit a non-array line at same level or higher)
  defp take_array_data_lines(lines, base_indent, opts) do
    # For tabular arrays: take lines at depth > base_indent that DON'T look like fields
    # For list arrays: take all lines > base_indent (list items and their nested content)

    # First, check if the first non-blank line starts with "-" (list array) or not (tabular)
    first_content = Enum.find(lines, fn line -> !line.is_blank end)

    is_list_array =
      case first_content do
        %{content: content} -> String.starts_with?(String.trim_leading(content), "-")
        nil -> false
      end

    if is_list_array do
      # For list arrays, we need to carefully track list items and their content
      # Find the expected indent of list items (should be base_indent + indent_size)
      list_item_indent =
        case first_content do
          %{indent: indent} -> indent
          nil -> base_indent + Map.get(opts, :indent_size, 2)
        end

      # Take all list items and their nested content
      # Stop at lines at list_item_indent level that don't start with "-"
      Enum.take_while(lines, fn line ->
        cond do
          line.is_blank ->
            true

          line.indent > list_item_indent ->
            # Nested content of list items
            true

          line.indent == list_item_indent ->
            # At list item level: only continue if it's a list marker
            String.starts_with?(String.trim_leading(line.content), "-")

          true ->
            false
        end
      end)
    else
      # Tabular array: take lines that don't look like fields
      Enum.take_while(lines, fn line ->
        cond do
          line.is_blank ->
            true

          line.indent > base_indent ->
            # Tabular array: take lines that don't look like "key: value"
            not String.match?(line.content, @field_pattern)

          true ->
            false
        end
      end)
    end
  end

  # Skip array data lines
  defp skip_array_data_lines(lines, base_indent) do
    # Use same logic as take_array_data_lines
    first_content = Enum.find(lines, fn line -> !line.is_blank end)

    is_list_array =
      case first_content do
        %{content: content} -> String.starts_with?(String.trim_leading(content), "-")
        nil -> false
      end

    remaining =
      if is_list_array do
        # Use same logic as take: find list item indent and skip accordingly
        list_item_indent =
          case first_content do
            %{indent: indent} -> indent
            nil -> base_indent + 2
          end

        Enum.drop_while(lines, fn line ->
          cond do
            line.is_blank ->
              true

            line.indent > list_item_indent ->
              true

            line.indent == list_item_indent ->
              String.starts_with?(String.trim_leading(line.content), "-")

            true ->
              false
          end
        end)
      else
        Enum.drop_while(lines, fn line ->
          cond do
            line.is_blank ->
              true

            line.indent > base_indent ->
              not String.match?(line.content, @field_pattern)

            true ->
              false
          end
        end)
      end

    {remaining, length(lines) - length(remaining)}
  end

  # Parse inline array from a line like "[2]: a,b"
  defp parse_inline_array_from_line(trimmed, rest) do
    # Extract: [N], [N|], [N\t] format
    case Regex.run(~r/^\[([^\]]+)\]:\s*(.*)$/, trimmed) do
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
    trimmed = String.trim_leading(content) |> String.replace_prefix("- ", "")

    # Use parse_inline_array_from_line directly since it handles [N]: format
    parse_inline_array_from_line(trimmed, rest)
  end

  # Parse fields from tabular header
  defp parse_fields(fields_str, delimiter) do
    # Split while respecting quoted strings (same logic as parse_delimited_values)
    delimiter_escaped = Regex.escape(delimiter)
    regex = ~r/("(?:[^"\\]|\\.)*"|[^#{delimiter_escaped}]+)/

    Regex.scan(regex, fields_str)
    |> Enum.map(&hd/1)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&unquote_key/1)
  end

  # Extract delimiter from array marker like [2], [2|], [2\t]
  defp extract_delimiter(array_marker) do
    cond do
      String.contains?(array_marker, "|") -> "|"
      String.contains?(array_marker, "\t") -> "\t"
      true -> ","
    end
  end

  # Parse delimited values from row
  defp parse_delimited_values(row_str, delimiter) do
    # Auto-detect delimiter if the declared delimiter doesn't seem to be present
    actual_delimiter =
      if delimiter == "," and String.contains?(row_str, "\t") and
           not String.contains?(row_str, ",") do
        "\t"
      else
        delimiter
      end

    # Split by delimiter, respecting quoted strings
    # This handles spaces around delimiters and empty tokens
    split_respecting_quotes(row_str, actual_delimiter)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_value/1)
  end

  # Split a string by delimiter, but don't split inside quoted strings
  defp split_respecting_quotes(str, delimiter) do
    # Use a simple state machine approach with iolist building for O(n) performance
    do_split_respecting_quotes(str, delimiter, [], false, [])
  end

  defp do_split_respecting_quotes("", _delimiter, current, _in_quote, acc) do
    # Reverse current iolist and convert to string, then reverse acc
    current_str = current |> Enum.reverse() |> IO.iodata_to_binary()
    Enum.reverse([current_str | acc])
  end

  defp do_split_respecting_quotes(<<"\\", char, rest::binary>>, delimiter, current, in_quote, acc) do
    # Escaped character - keep both backslash and char as iolist
    do_split_respecting_quotes(rest, delimiter, [<<char>>, "\\" | current], in_quote, acc)
  end

  defp do_split_respecting_quotes(<<"\"", rest::binary>>, delimiter, current, in_quote, acc) do
    # Toggle quote state
    do_split_respecting_quotes(rest, delimiter, ["\"" | current], not in_quote, acc)
  end

  defp do_split_respecting_quotes(<<char, rest::binary>>, delimiter, current, false, acc)
       when <<char>> == delimiter do
    # Delimiter outside quotes - split here, convert current iolist to string
    current_str = current |> Enum.reverse() |> IO.iodata_to_binary()
    do_split_respecting_quotes(rest, delimiter, [], false, [current_str | acc])
  end

  defp do_split_respecting_quotes(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    # Normal character - prepend to iolist
    do_split_respecting_quotes(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  # Parse a single value
  defp parse_value(str) do
    str |> String.trim() |> do_parse_value()
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

  defp has_decimal_or_exponent?(str) do
    String.contains?(str, ".") or String.contains?(str, "e") or String.contains?(str, "E")
  end

  defp normalize_decimal_number(num) when num == trunc(num), do: trunc(num)
  defp normalize_decimal_number(num), do: num

  # Remove quotes from key
  defp unquote_key("\"" <> _ = key) do
    key |> String.slice(1..-2//1) |> unescape_string()
  end

  defp unquote_key(key), do: key

  # Check if a key was originally quoted in the source line
  defp key_was_quoted?(original_line) do
    trimmed = String.trim_leading(original_line)
    String.starts_with?(trimmed, "\"")
  end

  # Update metadata with a key, checking if it was quoted
  defp add_key_to_metadata(key, was_quoted, metadata) do
    updated_metadata =
      if was_quoted do
        %{metadata | quoted_keys: MapSet.put(metadata.quoted_keys, key)}
      else
        metadata
      end

    %{updated_metadata | key_order: updated_metadata.key_order ++ [key]}
  end

  # Remove quotes and unescape string
  defp unquote_string("\"" <> _ = str) do
    if properly_quoted?(str) do
      str |> String.slice(1..-2//1) |> unescape_string()
    else
      raise DecodeError, message: "Unterminated string", input: str
    end
  end

  defp unquote_string(str), do: str

  # Check if a quoted string is properly terminated
  # The string should start and end with " and the ending " should not be escaped
  defp properly_quoted?(str) when byte_size(str) < 2, do: false

  defp properly_quoted?("\"" <> _ = str) do
    String.ends_with?(str, "\"") and not escaped_quote_at_end?(str)
  end

  defp properly_quoted?(_), do: false

  # Check if the closing quote is escaped
  defp escaped_quote_at_end?(str) do
    # Count consecutive backslashes before the final quote
    # If odd number, the quote is escaped; if even, it's not
    str
    # Remove final quote
    |> String.slice(0..-2//1)
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.take_while(&(&1 == ?\\))
    |> length()
    # Odd number means escaped
    |> rem(2) == 1
  end

  # Unescape string
  defp unescape_string(str) do
    # Per TOON spec: only \\, \", \n, \r, \t are valid escape sequences
    # We need to do replacements in the right order to handle \\ correctly
    # First replace \\ to a placeholder, then other escapes, then placeholder back to \
    str
    |> String.replace("\\\\", <<0>>)
    |> String.replace("\\\"", "\"")
    |> String.replace("\\n", "\n")
    |> String.replace("\\r", "\r")
    |> String.replace("\\t", "\t")
    |> validate_no_invalid_escapes(str)
    |> String.replace(<<0>>, "\\")
  end

  defp validate_no_invalid_escapes(processed, original) do
    if String.match?(processed, @invalid_escape_pattern) do
      raise DecodeError, message: "Invalid escape sequence", input: original
    else
      processed
    end
  end

  # Peek at next line's indent (skip blank lines)
  defp peek_next_indent([]), do: 0
  defp peek_next_indent([%{is_blank: true} | rest]), do: peek_next_indent(rest)
  defp peek_next_indent([%{indent: indent} | _]), do: indent

  # Get the indent of the first non-blank line
  defp get_first_content_indent([]), do: 0
  defp get_first_content_indent([%{is_blank: true} | rest]), do: get_first_content_indent(rest)
  defp get_first_content_indent([%{indent: indent} | _]), do: indent

  # Take lines at or above a specific indent level (for nested content at exact level)
  defp take_lines_at_level(lines, min_indent) do
    Enum.take_while(lines, fn line ->
      line.is_blank or line.indent >= min_indent
    end)
  end

  # Take lines that are more indented than base
  defp take_nested_lines(lines, base_indent) do
    # We need to handle blank lines carefully:
    # - Blank lines BETWEEN nested content should be included
    # - Blank lines AFTER nested content should NOT be included
    # We'll use a helper that tracks whether we're still in nested content
    take_nested_lines_helper(lines, base_indent, false)
  end

  defp take_nested_lines_helper([], _base_indent, _seen_content), do: []

  defp take_nested_lines_helper([line | rest], base_indent, seen_content) do
    cond do
      # Non-blank line that's more indented: include it and continue
      !line.is_blank and line.indent > base_indent ->
        [line | take_nested_lines_helper(rest, base_indent, true)]

      # Non-blank line at base level or less: stop here
      !line.is_blank ->
        []

      # Blank line: only include if the next non-blank line is still nested
      line.is_blank ->
        next_content_indent = peek_next_indent(rest)

        if next_content_indent > base_indent do
          [line | take_nested_lines_helper(rest, base_indent, seen_content)]
        else
          # Next content is at base level or less, so stop here
          []
        end
    end
  end

  # Skip lines that are more indented than base
  defp skip_nested_lines(lines, base_indent) do
    remaining = Enum.drop_while(lines, fn %{indent: indent} -> indent > base_indent end)
    {remaining, length(lines) - length(remaining)}
  end

  # Take lines for a list item (until next item marker at same level)
  defp take_item_lines(lines, base_indent) do
    Enum.take_while(lines, fn line ->
      # Take lines that are MORE indented than base (continuation lines)
      # Stop at next list item marker at the same level
      if line.indent == base_indent do
        not String.starts_with?(String.trim_leading(line.content), "- ")
      else
        line.indent > base_indent
      end
    end)
  end

  # Skip lines for a list item
  defp skip_item_lines(lines, base_indent) do
    remaining =
      Enum.drop_while(lines, fn line ->
        # Skip lines that are MORE indented than base (continuation lines)
        # Stop at next list item marker at the same level
        if line.indent == base_indent do
          not String.starts_with?(String.trim_leading(line.content), "- ")
        else
          line.indent > base_indent
        end
      end)

    {remaining, length(lines) - length(remaining)}
  end
end
