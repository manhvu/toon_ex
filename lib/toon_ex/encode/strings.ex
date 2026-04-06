defmodule ToonEx.Encode.Strings do
  @moduledoc """
  String encoding utilities for TOON format.

  Handles quote detection, escaping, and key validation.
  """

  # Pre-compiled regex patterns for performance
  # @number_pattern removed - replaced with binary character range checks in looks_like_number?/1

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
  # Performance: Returns binary directly instead of iodata list to reduce memory overhead
  @spec encode_string(String.t(), String.t()) :: binary()
  def encode_string(string, delimiter \\ ",") when is_binary(string) do
    if safe_unquoted?(string, delimiter) do
      string
    else
      # Direct binary construction: "escaped_string"
      <<?", escape_string(string)::binary, ?">>
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
  # Performance: Returns binary directly instead of iodata list
  @spec encode_key(String.t()) :: binary()
  def encode_key(key) when is_binary(key) do
    if safe_key?(key) do
      key
    else
      # Direct binary construction: "escaped_key"
      <<?", escape_string(key)::binary, ?">>
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
  # Performance: Binary character range checks instead of regex
  # Matches: ^[A-Za-z_][A-Za-z0-9_.]*$
  @spec safe_key?(String.t()) :: boolean()
  def safe_key?(<<first, rest::binary>>) do
    do_safe_key_first?(first) and do_safe_key_rest?(rest)
  end

  def safe_key?(_), do: false

  # First character: must be A-Z, a-z, or _
  defp do_safe_key_first?(c) when c in ?A..?Z, do: true
  defp do_safe_key_first?(c) when c in ?a..?z, do: true
  defp do_safe_key_first?(?_), do: true
  defp do_safe_key_first?(_), do: false

  # Remaining characters: A-Z, a-z, 0-9, _, or .
  defp do_safe_key_rest?(<<>>), do: true
  defp do_safe_key_rest?(<<c, rest::binary>>) when c in ?A..?Z, do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<c, rest::binary>>) when c in ?a..?z, do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<c, rest::binary>>) when c in ?0..?9, do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<?_, rest::binary>>), do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<?., rest::binary>>), do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(_), do: false

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
    do_escape_string_binary(string, <<>>)
  end

  # Performance: Single-pass binary construction - avoids iodata list overhead
  # Returns binary directly instead of iodata list
  @compile {:inline, do_escape_string_binary: 2}
  defp do_escape_string_binary(<<>>, acc), do: acc

  defp do_escape_string_binary(<<?\\, rest::binary>>, acc),
    do: do_escape_string_binary(rest, <<acc::binary, 92, 92>>)

  defp do_escape_string_binary(<<?", rest::binary>>, acc),
    do: do_escape_string_binary(rest, <<acc::binary, 92, 34>>)

  defp do_escape_string_binary(<<?\n, rest::binary>>, acc),
    do: do_escape_string_binary(rest, <<acc::binary, 92, 110>>)

  defp do_escape_string_binary(<<?\r, rest::binary>>, acc),
    do: do_escape_string_binary(rest, <<acc::binary, 92, 114>>)

  defp do_escape_string_binary(<<?\t, rest::binary>>, acc),
    do: do_escape_string_binary(rest, <<acc::binary, 92, 116>>)

  # Fast-path for ASCII bytes that don't need escaping
  defp do_escape_string_binary(<<byte, rest::binary>>, acc) when byte < 128,
    do: do_escape_string_binary(rest, <<acc::binary, byte>>)

  # Multi-byte UTF-8 characters (bytes >= 128) - copy as-is (they never need escaping per TOON spec)
  defp do_escape_string_binary(<<byte, rest::binary>>, acc) when byte >= 128,
    do: do_escape_string_binary(rest, <<acc::binary, byte>>)

  # Private helpers

  defp has_leading_or_trailing_space?(string) do
    String.starts_with?(string, " ") or String.ends_with?(string, " ")
  end

  # Performance: Wrapper functions for single-pass binary scans
  defp contains_structure_chars?(string), do: do_contains_structure_chars?(string)
  defp contains_control_chars?(string), do: do_contains_control_chars?(string)

  # Performance: Binary pattern matching instead of list membership check
  @compile {:inline, literal?: 1}
  defp literal?("true"), do: true
  defp literal?("false"), do: true
  defp literal?("null"), do: true
  defp literal?(_), do: false

  # Performance: Binary character range checks instead of regex
  # Matches: /^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i
  defp looks_like_number?(string) do
    do_looks_like_number?(string, :start)
  end

  # State machine for number parsing
  # :start - optional minus, then digits
  defp do_looks_like_number?(<<?-, rest::binary>>, :start),
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(<<c, rest::binary>>, :start) when c in ?0..?9,
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(_, :start), do: false

  # :digits - digits, or dot, or exponent
  defp do_looks_like_number?(<<>>, :digits), do: true

  defp do_looks_like_number?(<<c, rest::binary>>, :digits) when c in ?0..?9,
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(<<?., rest::binary>>, :digits),
    do: do_looks_like_number?(rest, :frac)

  defp do_looks_like_number?(<<c, rest::binary>>, :digits) when c == ?e or c == ?E,
    do: do_looks_like_number?(rest, :exp_sign)

  defp do_looks_like_number?(_, :digits), do: false

  # :frac - digits after decimal point, or exponent
  defp do_looks_like_number?(<<>>, :frac), do: true

  defp do_looks_like_number?(<<c, rest::binary>>, :frac) when c in ?0..?9,
    do: do_looks_like_number?(rest, :frac)

  defp do_looks_like_number?(<<c, rest::binary>>, :frac) when c == ?e or c == ?E,
    do: do_looks_like_number?(rest, :exp_sign)

  defp do_looks_like_number?(_, :frac), do: false

  # :exp_sign - optional +/- after exponent, then digits
  defp do_looks_like_number?(<<c, rest::binary>>, :exp_sign) when c == ?+ or c == ?-,
    do: do_looks_like_number?(rest, :exp_digits)

  defp do_looks_like_number?(<<c, rest::binary>>, :exp_sign) when c in ?0..?9,
    do: do_looks_like_number?(rest, :exp_digits)

  defp do_looks_like_number?(_, :exp_sign), do: false

  # :exp_digits - digits after exponent
  defp do_looks_like_number?(<<>>, :exp_digits), do: true

  defp do_looks_like_number?(<<c, rest::binary>>, :exp_digits) when c in ?0..?9,
    do: do_looks_like_number?(rest, :exp_digits)

  defp do_looks_like_number?(_, :exp_digits), do: false

  # Single-pass binary scan for structure characters - avoids multiple String.contains? calls
  # Performance: Single-pass binary scan for structure characters
  @compile {:inline, do_contains_structure_chars?: 1}
  defp do_contains_structure_chars?(<<>>), do: false
  defp do_contains_structure_chars?(<<?:, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?[, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?], _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?{, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?}, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?(, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<41, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?", _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?\\, _rest::binary>>), do: true

  defp do_contains_structure_chars?(<<byte, rest::binary>>) when byte < 128,
    do: do_contains_structure_chars?(rest)

  defp do_contains_structure_chars?(<<byte, rest::binary>>) when byte >= 128,
    do: do_contains_structure_chars?(rest)

  # Performance: Use String.contains? which correctly handles variable delimiters
  # Binary pattern matching with variables doesn't work for value comparison in function heads
  @compile {:inline, contains_delimiter?: 2}
  defp contains_delimiter?(string, delimiter) do
    String.contains?(string, delimiter)
  end

  # Performance: Single-pass binary scan for control characters
  @compile {:inline, do_contains_control_chars?: 1}
  defp do_contains_control_chars?(<<>>), do: false
  defp do_contains_control_chars?(<<?\n, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\r, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\t, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\b, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\f, _rest::binary>>), do: true

  defp do_contains_control_chars?(<<byte, rest::binary>>) when byte < 128,
    do: do_contains_control_chars?(rest)

  defp do_contains_control_chars?(<<byte, rest::binary>>) when byte >= 128,
    do: do_contains_control_chars?(rest)

  defp starts_with_hyphen?(string) do
    String.starts_with?(string, "-")
  end
end
