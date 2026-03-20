defmodule Toon.Decode.Parser do
  @moduledoc """
  NimbleParsec-based parser for TOON format.

  This module defines the grammar for parsing TOON format strings.
  """

  import NimbleParsec

  # Basic tokens
  @colon string(":")
  @space string(" ")
  @delimiter choice([string(","), string("\t"), string("|")])

  # Quoted string: "..."
  quoted_string =
    ignore(string("\""))
    |> repeat(
      choice([
        string("\\\"") |> replace("\""),
        string("\\\\") |> replace("\\"),
        string("\\n") |> replace("\n"),
        string("\\r") |> replace("\r"),
        string("\\t") |> replace("\t"),
        utf8_string([not: ?", not: ?\\], min: 1)
      ])
    )
    |> ignore(string("\""))
    |> reduce({IO, :iodata_to_binary, []})

  # Unquoted string: alphanumeric and some special chars
  unquoted_string =
    utf8_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?., ?-], min: 1)

  # Quoted key: tag specially to track during path expansion
  quoted_key =
    quoted_string
    |> unwrap_and_tag(:quoted_key)

  # Key: quoted or unquoted
  key =
    choice([
      quoted_key,
      unquoted_string |> unwrap_and_tag(:key)
    ])

  # Null literal
  null_value = string("null") |> replace(nil) |> unwrap_and_tag(:null)

  # Boolean literals
  bool_value =
    choice([
      string("true") |> replace(true),
      string("false") |> replace(false)
    ])
    |> unwrap_and_tag(:bool)

  # Number: integer, float, or exponent notation (e.g., 1e6, -1E+03, 2.5e-2)
  number_value =
    optional(ascii_string([?-], 1))
    |> concat(ascii_string([?0..?9], min: 1))
    |> optional(ascii_string([?.], 1) |> concat(ascii_string([?0..?9], min: 1)))
    |> optional(
      ascii_string([?e, ?E], 1)
      |> concat(optional(ascii_string([?+, ?-], 1)))
      |> concat(ascii_string([?0..?9], min: 1))
    )
    |> reduce({Enum, :join, [""]})
    |> map({__MODULE__, :parse_number, []})
    |> unwrap_and_tag(:number)

  # String value: quoted or unquoted
  string_value =
    choice([
      quoted_string,
      # Unquoted value (not starting with special chars)
      utf8_string([not: ?:, not: ?,, not: ?\n, not: ?\r], min: 1)
      |> map({String, :trim, []})
    ])
    |> unwrap_and_tag(:string)

  # Primitive value
  primitive_value =
    choice([
      null_value,
      bool_value,
      number_value,
      string_value
    ])

  # Array length marker: [123] or [123\t] or [123|]
  # Per TOON spec v2.0, [#N] format is no longer valid
  # Per TOON spec Section 6, non-comma delimiters are indicated in the header
  array_length =
    ignore(string("["))
    |> ascii_string([?0..?9], min: 1)
    |> optional(ignore(choice([string("\t"), string("|")])))
    |> ignore(string("]"))
    |> map({String, :to_integer, []})
    |> unwrap_and_tag(:array_length)

  # Optional whitespace (for tolerating spaces around delimiters)
  optional_ws = ignore(repeat(ascii_char([?\s])))

  # Delimiter with optional surrounding whitespace
  delimiter_with_ws =
    optional_ws
    |> concat(ignore(@delimiter))
    |> concat(optional_ws)

  # Empty value (for handling empty tokens like a,,c)
  empty_value = lookahead(choice([@delimiter, eos()])) |> replace("") |> unwrap_and_tag(:string)

  # Array value: either a primitive or empty string
  array_value = choice([primitive_value, empty_value])

  # Inline array values: val1,val2,val3 (or tab/pipe separated)
  # Supports spaces around delimiters and empty tokens
  inline_array_values =
    array_value
    |> repeat(delimiter_with_ws |> concat(array_value))
    |> tag(:inline_array)

  # Key-value pair: "key: "
  empty_kv =
    key
    |> ignore(@colon)
    |> ignore(@space)
    |> reduce({__MODULE__, :make_empty_kv, []})

  # Key-value pair: key: value
  simple_kv =
    key
    |> ignore(@colon)
    |> ignore(@space)
    |> concat(primitive_value)
    |> reduce({__MODULE__, :make_kv, []})

  # Empty array: key[0]:
  empty_array_line =
    key
    |> concat(array_length)
    |> ignore(@colon)
    |> reduce({__MODULE__, :make_empty_array_kv, []})

  # Inline array: key[N]: val1,val2,val3
  inline_array_line =
    key
    |> concat(array_length)
    |> ignore(@colon)
    |> ignore(@space)
    |> concat(inline_array_values)
    |> reduce({__MODULE__, :make_array_kv, []})

  # Line parser (try inline_array_line before empty_array_line)
  line =
    choice([
      inline_array_line,
      empty_array_line,
      simple_kv,
      empty_kv
    ])

  defparsec(:parse_line, line)

  # Public helper functions

  @doc false
  def parse_number(str) when is_binary(str) do
    cond do
      # Exponent notation (e.g., 1e6, -1E+03, 2.5e-2)
      String.contains?(str, "e") or String.contains?(str, "E") ->
        # Float.parse handles exponent notation
        {float, ""} = Float.parse(str)
        # If result is a whole number, return as integer
        if float == trunc(float), do: trunc(float), else: float

      # Decimal float (e.g., 1.5, -2.0)
      String.contains?(str, ".") ->
        String.to_float(str)

      # Integer
      true ->
        String.to_integer(str)
    end
  end

  @doc false
  def make_kv([{_key_type, key}, {_type, value}]) do
    {key, value}
  end

  @doc false
  def make_empty_kv([{_key_type, key}]) do
    {key, %{}}
  end

  @doc false
  def make_empty_array_kv([{_key_type, key}, {:array_length, _len}]) do
    {key, []}
  end

  @doc false
  def make_array_kv([{_key_type, key}, {:array_length, _len}, {:inline_array, values}]) do
    array_values = Enum.map(values, fn {_type, val} -> val end)
    {key, array_values}
  end
end
