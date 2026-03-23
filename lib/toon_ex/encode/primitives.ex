defmodule ToonEx.Encode.Primitives do
  @moduledoc """
  Encoding of primitive TOON values (nil, boolean, number, string).
  """

  alias ToonEx.Constants
  alias ToonEx.Encode.Strings

  @doc """
  Encodes a primitive value to TOON format.

  ## Examples

      iex> ToonEx.Encode.Primitives.encode(nil, ",")
      "null"

      iex> ToonEx.Encode.Primitives.encode(true, ",")
      "true"

      iex> ToonEx.Encode.Primitives.encode(false, ",")
      "false"

      iex> ToonEx.Encode.Primitives.encode(42, ",")
      "42"

      iex> ToonEx.Encode.Primitives.encode(3.14, ",")
      "3.14"

      iex> ToonEx.Encode.Primitives.encode("hello", ",")
      "hello"

      iex> ToonEx.Encode.Primitives.encode("hello world", ",")
      ~s("hello world")
  """
  @spec encode(term(), String.t()) :: iodata()
  def encode(nil, _delimiter), do: Constants.null_literal()
  def encode(true, _delimiter), do: Constants.true_literal()
  def encode(false, _delimiter), do: Constants.false_literal()

  def encode(value, _delimiter) when is_integer(value) do
    Integer.to_string(value)
  end

  def encode(value, _delimiter) when is_float(value) do
    # Format float without scientific notation
    format_float(value)
  end

  def encode(value, delimiter) when is_binary(value) do
    Strings.encode_string(value, delimiter)
  end

  # Private helpers

  @doc false
  @spec format_float(float()) :: String.t()

  defp format_float(value) when is_float(value) do
    cond do
      # IEEE 754 NaN: the only float not equal to itself
      # credo:disable-for-lines:2
      value != value ->
        Constants.null_literal()

      value > 1.0e308 or value < -1.0e308 ->
        Constants.null_literal()

      # Whole-number float — encode without decimal point per TOON spec
      trunc(value) == value ->
        Integer.to_string(trunc(value))

      true ->
        str = Float.to_string(value)
        if scientific?(str), do: to_decimal(value), else: str
    end
  end

  # `:erlang.float_to_binary` uses exponential notation when abs < 0.1 or
  # abs >= 1.0e16; `Float.to_string` (Ryu) uses it outside a similar range.
  defp scientific?(str), do: String.contains?(str, "e") or String.contains?(str, "E")

  # Convert a float that Float.to_string/1 represented in scientific notation
  # to a plain decimal string, trimming trailing zeros.
  #
  # Strategy: ask :erlang.float_to_binary/2 for enough decimal places to
  # preserve all 15–17 significant digits, then strip trailing zeros in one pass.
  defp to_decimal(value) do
    abs_val = abs(value)

    # Number of decimal places needed so no significant digit is lost.
    decimals =
      cond do
        abs_val < 1.0 ->
          # e.g. 1.0e-10 → neg_exp ≈ 10 → decimals = 27
          neg_exp = abs_val |> :math.log10() |> abs() |> Float.ceil() |> trunc()
          min(neg_exp + 17, 324)

        true ->
          # e.g. 1.23e15 → integer part has 16 digits → only 1 decimal needed
          exp = abs_val |> :math.log10() |> Float.floor() |> trunc()
          max(17 - exp, 1)
      end

    raw = :erlang.float_to_binary(value, [{:decimals, decimals}])
    trim_trailing_zeros(raw)
  end

  # Splits on "." and strips trailing "0" from the fractional part.
  # If the fractional part becomes empty the decimal point is also dropped,
  # which correctly represents whole numbers (should never occur here since
  # whole-number floats are caught above, but defensive).
  defp trim_trailing_zeros(str) do
    case String.split(str, ".", parts: 2) do
      [int, frac] ->
        stripped = String.trim_trailing(frac, "0")
        if stripped == "", do: int, else: int <> "." <> stripped

      [int] ->
        int
    end
  end
end
