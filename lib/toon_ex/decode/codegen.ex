defmodule ToonEx.Decode.Codegen do
  @moduledoc """
  Compile-time code generation utilities for the TOON decoder.

  Inspired by `Jason.Codegen`, this module provides macros for generating
  efficient byte-level dispatch tables at compile time. This replaces runtime
  regex checks and `String.contains?` calls with O(1) binary pattern matching.

  ## How it works

  The `bytecase/2` macro generates a `case` expression on a binary where each
  clause matches a specific leading byte. This is more efficient than calling
  `String.starts_with?/2` or regex matching because:

  1. The BEAM compiler optimizes binary pattern matching into a jump table
  2. No intermediate string allocations
  3. The dispatch is O(1) regardless of the number of clauses

  ## Example

      bytecase data do
        _ in ~c'0123456789', rest ->
          parse_number(rest)
        _ in ~c'"', rest ->
          parse_string(rest)
        _, rest ->
          error(rest)
      end

  Generates:

      case data do
        <<48, rest::bits>> -> parse_number(rest)
        <<49, rest::bits>> -> parse_number(rest)
        ...
        <<34, rest::bits>> -> parse_string(rest)
        <<byte, rest::bits>> -> error(rest)
      end
  """

  @doc """
  Builds a compile-time jump table from byte ranges.

  Returns a list of `{byte_value, action}` tuples suitable for generating
  case clauses.
  """
  def jump_table(ranges, default) do
    ranges
    |> ranges_to_orddict()
    |> :array.from_orddict(default)
    |> :array.to_orddict()
  end

  def jump_table(ranges, default, max) do
    ranges
    |> ranges_to_orddict()
    |> :array.from_orddict(default)
    |> resize(max)
    |> :array.to_orddict()
  end

  @doc """
  Generates a `case` expression that dispatches on the first byte of a binary.

  ## Clause syntax

      bytecase var do
        _ in ~c'abc', rest ->
          # matches bytes 97, 98, 99
          handle_abc(rest)

        _ in 0..31, rest ->
          # matches bytes 0-31
          handle_control(rest)

        _, rest ->
          # default clause
          handle_other(rest)
      end

  The `_` in patterns is the byte variable (unused but required for syntax).
  The second element `rest` captures the remaining binary.
  """
  defmacro bytecase(var, do: clauses) do
    {ranges, default, literals} = clauses_to_ranges(clauses, [], __CALLER__)

    jump_table = jump_table(ranges, default)

    quote do
      case unquote(var) do
        unquote(jump_table_to_clauses(jump_table, literals))
      end
    end
  end

  @doc """
  Like `bytecase/2` but with an explicit max byte value for the jump table.
  Useful when you want to cover all bytes up to a certain value.
  """
  defmacro bytecase(var, max, do: clauses) do
    {ranges, default, empty} = clauses_to_ranges(clauses, [], __CALLER__)

    jump_table = jump_table(ranges, default, max)

    quote do
      case unquote(var) do
        unquote(jump_table_to_clauses(jump_table, empty))
      end
    end
  end

  # Private helpers

  defp clauses_to_ranges([{:->, _, [[{:in, _, [byte, range]}, rest], action]} | tail], acc, env) do
    range = Macro.expand(range, env)
    clauses_to_ranges(tail, [{range, {byte, rest, action}} | acc], env)
  end

  defp clauses_to_ranges([{:->, _, [[default, rest], action]} | tail], acc, _env) do
    {Enum.reverse(acc), {default, rest, action}, literal_clauses(tail)}
  end

  defp literal_clauses(clauses) do
    Enum.map(clauses, fn {:->, _, [[literal], action]} ->
      {literal, action}
    end)
  end

  defp jump_table_to_clauses([{val, {{:_, _, _}, rest, action}} | tail], empty) do
    quote do
      <<unquote(val), unquote(rest)::bits>> ->
        unquote(action)
    end ++ jump_table_to_clauses(tail, empty)
  end

  defp jump_table_to_clauses([{val, {byte, rest, action}} | tail], empty) do
    quote do
      <<unquote(byte), unquote(rest)::bits>> when unquote(byte) === unquote(val) ->
        unquote(action)
    end ++ jump_table_to_clauses(tail, empty)
  end

  defp jump_table_to_clauses([], literals) do
    Enum.flat_map(literals, fn {pattern, action} ->
      quote do
        unquote(pattern) ->
          unquote(action)
      end
    end)
  end

  defp resize(array, size), do: :array.resize(size, array)

  defp ranges_to_orddict(ranges) do
    ranges
    |> Enum.flat_map(fn
      {int, value} when is_integer(int) ->
        [{int, value}]

      {enum, value} ->
        Enum.map(enum, &{&1, value})
    end)
    |> :orddict.from_list()
  end
end
