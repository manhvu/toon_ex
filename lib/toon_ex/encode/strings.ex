defmodule ToonEx.Encode.Strings do
  @moduledoc """
  String encoding utilities for TOON format.

  Handles quote detection, escaping, and key validation.
  """

  alias ToonEx.Constants

  # Pre-compiled regex patterns for performance
  @key_pattern ~r/^[A-Z_][\w.]*$/i
  @number_pattern ~r/^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i

  @doc """
  Encodes a string value, adding quotes if necessary.

  ## Examples

      iex> ToonEx.Encode.Strings.encode_string("hello")
      "hello"

      iex> ToonEx.Encode.Strings.encode_string("") |> IO.iodata_to_binary()
      ~s("")

      iex> ToonEx.Encode.Strings.encode_string("hello world")
      "hello world"

      iex> ToonEx.Encode.Strings.encode_string("line1\\nline2") |> IO.iodata_to_binary()
      ~s("line1\\\\nline2")
  """
  @spec encode_string(String.t(), String.t()) :: binary() | nonempty_list(binary())
  def encode_string(string, delimiter \\ ",") when is_binary(string) do
    if safe_unquoted?(string, delimiter) do
      string
    else
      [Constants.double_quote(), escape_string(string), Constants.double_quote()]
    end
  end

  @doc """
  Encodes a key, adding quotes if necessary.

  Keys have stricter requirements than values:
  - Must match /^[A-Z_][\\w.]*$/i (alphanumeric, underscore, dot)
  - Numbers-only keys must be quoted
  - Keys with special characters must be quoted

  ## Examples

      iex> ToonEx.Encode.Strings.encode_key("name")
      "name"

      iex> ToonEx.Encode.Strings.encode_key("user_name")
      "user_name"

      iex> ToonEx.Encode.Strings.encode_key("user.name")
      "user.name"

      iex> ToonEx.Encode.Strings.encode_key("user name") |> IO.iodata_to_binary()
      ~s("user name")

      iex> ToonEx.Encode.Strings.encode_key("123") |> IO.iodata_to_binary()
      ~s("123")
  """
  @spec encode_key(String.t()) :: String.t() | [String.t(), ...]
  def encode_key(key) when is_binary(key) do
    if safe_key?(key) do
      key
    else
      [Constants.double_quote(), escape_string(key), Constants.double_quote()]
    end
  end

  @doc """
  Checks if a string can be used unquoted as a value.

  A string is safe unquoted if:
  - It's not empty
  - It doesn't have leading or trailing spaces
  - It's not a literal (true, false, null)
  - It doesn't look like a number
  - It doesn't contain structure characters or delimiters
  - It doesn't contain control characters
  - It doesn't start with a hyphen

  ## Examples

      iex> ToonEx.Encode.Strings.safe_unquoted?("hello", ",")
      true

      iex> ToonEx.Encode.Strings.safe_unquoted?("", ",")
      false

      iex> ToonEx.Encode.Strings.safe_unquoted?(" hello", ",")
      false

      iex> ToonEx.Encode.Strings.safe_unquoted?("true", ",")
      false

      iex> ToonEx.Encode.Strings.safe_unquoted?("42", ",")
      false
  """
  @spec safe_unquoted?(String.t(), String.t()) :: boolean()
  def safe_unquoted?(string, delimiter) when is_binary(string) do
    not (string == "" or needs_quoting_basic?(string) or
           needs_quoting_delimiter?(string, delimiter))
  end

  # Check basic quoting requirements (leading/trailing spaces, literals, numbers, structure)
  defp needs_quoting_basic?(string) do
    has_leading_or_trailing_space?(string) or
      literal?(string) or
      looks_like_number?(string) or
      contains_structure_chars?(string) or
      contains_control_chars?(string) or
      starts_with_hyphen?(string)
  end

  # Check delimiter-specific quoting requirements
  defp needs_quoting_delimiter?(string, delimiter) do
    contains_delimiter?(string, delimiter)
  end

  @doc """
  Checks if a string can be used as an unquoted key.

  A key is safe if it matches /^[A-Z_][\\w.]*$/i

  ## Examples

      iex> ToonEx.Encode.Strings.safe_key?("name")
      true

      iex> ToonEx.Encode.Strings.safe_key?("user_name")
      true

      iex> ToonEx.Encode.Strings.safe_key?("User123")
      true

      iex> ToonEx.Encode.Strings.safe_key?("user.name")
      true

      iex> ToonEx.Encode.Strings.safe_key?("user-name")
      false

      iex> ToonEx.Encode.Strings.safe_key?("123")
      false
  """
  @spec safe_key?(String.t()) :: boolean()
  def safe_key?(key) when is_binary(key) do
    Regex.match?(@key_pattern, key)
  end

  @doc """
  Escapes special characters in a string.

  ## Examples

      iex> ToonEx.Encode.Strings.escape_string("hello")
      "hello"

      iex> ToonEx.Encode.Strings.escape_string("line1\\nline2")
      "line1\\\\nline2"

      iex> result = ToonEx.Encode.Strings.escape_string(~s(say "hello"))
      iex> String.contains?(result, ~s(\\"))
      true
  """
  @spec escape_string(String.t()) :: String.t()
  def escape_string(string) when is_binary(string) do
    do_escape_string(string, [])
  end

  # Single-pass binary pattern matching for escaping - avoids 5x String.replace overhead
  @compile {:inline, do_escape_string: 2}
  defp do_escape_string(<<>>, acc), do: acc |> :lists.reverse() |> IO.iodata_to_binary()

  defp do_escape_string(<<?\\, rest::binary>>, acc),
    do: do_escape_string(rest, ["\\\\" | acc])

  defp do_escape_string(<<?", rest::binary>>, acc),
    do: do_escape_string(rest, ["\\\"" | acc])

  defp do_escape_string(<<?\n, rest::binary>>, acc),
    do: do_escape_string(rest, ["\\n" | acc])

  defp do_escape_string(<<?\r, rest::binary>>, acc),
    do: do_escape_string(rest, ["\\r" | acc])

  defp do_escape_string(<<?\t, rest::binary>>, acc),
    do: do_escape_string(rest, ["\\t" | acc])

  # Fast-path for ASCII bytes that don't need escaping
  defp do_escape_string(<<byte, rest::binary>>, acc) when byte < 128,
    do: do_escape_string(rest, [<<byte>> | acc])

  # Multi-byte UTF-8 characters - copy as-is (they never need escaping per TOON spec)
  defp do_escape_string(<<byte::utf8, rest::binary>>, acc),
    do: do_escape_string(rest, [<<byte::utf8>> | acc])

  # Private helpers

  defp has_leading_or_trailing_space?(string) do
    String.starts_with?(string, " ") or String.ends_with?(string, " ")
  end

  # Performance: Binary pattern matching instead of list membership check
  @compile {:inline, literal?: 1}
  defp literal?("true"), do: true
  defp literal?("false"), do: true
  defp literal?("null"), do: true
  defp literal?(_), do: false

  defp looks_like_number?(string) do
    # Per TOON spec Section 7.2: matches /^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i
    # Uses pre-compiled pattern for performance
    Regex.match?(@number_pattern, string)
  end

  # Single-pass binary scan for structure characters - avoids multiple String.contains? calls
  defp contains_structure_chars?(string) do
    do_contains_structure_chars?(string)
  end

  @compile {:inline, do_contains_structure_chars?: 1}
  defp do_contains_structure_chars?(<<>>), do: false
  defp do_contains_structure_chars?(<<?:, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?[, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?], _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?{, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?}, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?(, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?), _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?", _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?\\, _rest::binary>>), do: true
  # Skip ASCII bytes that aren't structure chars
  defp do_contains_structure_chars?(<<byte, rest::binary>>) when byte < 128,
    do: do_contains_structure_chars?(rest)

  # Skip multi-byte UTF-8 characters
  defp do_contains_structure_chars?(<<_byte::utf8, rest::binary>>),
    do: do_contains_structure_chars?(rest)

  # Performance: Single-pass binary scan instead of String.contains?
  @compile {:inline, contains_delimiter?: 2}
  defp contains_delimiter?(string, <<delimiter>>) do
    do_contains_delimiter?(string, delimiter)
  end

  defp do_contains_delimiter?(<<>>, _delimiter), do: false
  defp do_contains_delimiter?(<<delimiter, _rest::binary>>, delimiter), do: true

  defp do_contains_delimiter?(<<_byte, rest::binary>>, delimiter),
    do: do_contains_delimiter?(rest, delimiter)

  # Single-pass binary scan for control characters - avoids multiple String.contains? calls
  defp contains_control_chars?(string) do
    do_contains_control_chars?(string)
  end

  @compile {:inline, do_contains_control_chars?: 1}
  defp do_contains_control_chars?(<<>>), do: false
  defp do_contains_control_chars?(<<?\n, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\r, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\t, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\b, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\f, _rest::binary>>), do: true
  # Skip ASCII bytes that aren't control chars
  defp do_contains_control_chars?(<<byte, rest::binary>>) when byte < 128,
    do: do_contains_control_chars?(rest)

  # Skip multi-byte UTF-8 characters
  defp do_contains_control_chars?(<<_byte::utf8, rest::binary>>),
    do: do_contains_control_chars?(rest)

  defp starts_with_hyphen?(string) do
    String.starts_with?(string, "-")
  end
end
