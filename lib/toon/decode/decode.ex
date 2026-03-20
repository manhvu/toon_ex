defmodule Toon.Decode do
  @moduledoc """
  Main decoder for TOON format.

  Parses TOON format strings and converts them to Elixir data structures.
  """

  alias Toon.Decode.{Options, StructuralParser}
  alias Toon.DecodeError

  @identifier_segment_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @typedoc "Decoded TOON value"
  @type decoded :: nil | boolean() | binary() | number() | list() | map()

  @doc """
  Decodes a TOON format string to Elixir data.

  ## Options

    * `:keys` - How to decode map keys: `:strings` | `:atoms` | `:atoms!` (default: `:strings`)

  ## Examples

      iex> Toon.Decode.decode("name: Alice")
      {:ok, %{"name" => "Alice"}}

      iex> Toon.Decode.decode("age: 30")
      {:ok, %{"age" => 30}}

      iex> Toon.Decode.decode("tags[2]: a,b")
      {:ok, %{"tags" => ["a", "b"]}}

      iex> Toon.Decode.decode("name: Alice", keys: :atoms)
      {:ok, %{name: "Alice"}}
  """
  @spec decode(String.t(), keyword()) :: {:ok, term()} | {:error, DecodeError.t()}
  def decode(string, opts \\ []) when is_binary(string) do
    start_time = System.monotonic_time()
    metadata = %{input_size: byte_size(string)}

    :telemetry.execute([:toon, :decode, :start], %{system_time: System.system_time()}, metadata)

    result =
      case Options.validate(opts) do
        {:ok, validated_opts} ->
          try do
            decoded = do_decode(string, validated_opts)
            {:ok, decoded}
          rescue
            e in DecodeError ->
              {:error, e}

            e ->
              {:error,
               DecodeError.exception(
                 message: "Decode failed: #{Exception.message(e)}",
                 input: string
               )}
          end

        {:error, error} ->
          {:error,
           DecodeError.exception(
             message: "Invalid options: #{Exception.message(error)}",
             reason: error
           )}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, _decoded} ->
        :telemetry.execute(
          [:toon, :decode, :stop],
          %{duration: duration},
          metadata
        )

      {:error, error} ->
        :telemetry.execute(
          [:toon, :decode, :exception],
          %{duration: duration},
          Map.put(metadata, :error, error)
        )
    end

    result
  end

  @doc """
  Decodes a TOON format string to Elixir data, raising on error.

  ## Examples

      iex> Toon.Decode.decode!("name: Alice")
      %{"name" => "Alice"}

      iex> Toon.Decode.decode!("count: 42")
      %{"count" => 42}
  """
  @spec decode!(String.t(), keyword()) :: decoded()
  def decode!(string, opts \\ []) when is_binary(string) do
    case decode(string, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  # Private functions

  @spec do_decode(String.t(), map()) :: decoded()
  defp do_decode(string, opts) do
    # Use structural parser for full TOON support
    case StructuralParser.parse(string, opts) do
      {:ok, {result, metadata}} ->
        maybe_expand_paths(result, metadata, opts)

      {:error, error} ->
        raise error
    end
  end

  # Path expansion per spec v1.5 section 13.4 - entry point with metadata
  defp maybe_expand_paths(result, metadata, %{expand_paths: "safe"} = opts) when is_map(result) do
    quoted_keys = metadata.quoted_keys
    strict = Map.get(opts, :strict, true)
    ordered_keys = get_ordered_keys(result, metadata.key_order)


    Enum.reduce(ordered_keys, %{}, fn key, acc ->
      value = Map.get(result, key) |> maybe_expand_paths_nested(opts)
      process_key(acc, key, value, quoted_keys, strict)
    end)
  end

  defp maybe_expand_paths(result, _metadata, opts), do: maybe_expand_paths_nested(result, opts)

  # Get keys in document order, falling back to map keys
  defp get_ordered_keys(result, []), do: Map.keys(result)
  defp get_ordered_keys(result, key_order), do: Enum.filter(key_order, &Map.has_key?(result, &1))

  # Process a single key - either expand dotted path or insert directly
  defp process_key(acc, key, value, quoted_keys, strict) do

    if should_expand?(key, quoted_keys) do
      nested = build_nested(String.split(key, "."), value)
      deep_merge_with_conflict(acc, nested, strict)
    else
      insert_key(acc, key, value, strict)
    end
  end

  defp should_expand?(key, quoted_keys) do
    expandable_key?(key) and not MapSet.member?(quoted_keys, key)
  end

  # Insert key with conflict checking
  defp insert_key(acc, key, value, _strict) when not is_map_key(acc, key) do
    Map.put(acc, key, value)
  end

  defp insert_key(_acc, key, _value, true = _strict) do
    raise DecodeError, message: "Path expansion conflict at key '#{key}'", reason: :path_conflict
  end

  defp insert_key(acc, key, value, false = _strict) do
    Map.put(acc, key, value)
  end

  # Recursive path expansion for nested structures (no metadata needed)
  defp maybe_expand_paths_nested(result, %{expand_paths: "safe"} = opts) when is_list(result) do
    Enum.map(result, &maybe_expand_paths_nested(&1, opts))
  end

  defp maybe_expand_paths_nested(result, _opts), do: result

  # IdentifierSegment: [A-Za-z_][A-Za-z0-9_]*
  defp expandable_key?(key) do
    String.contains?(key, ".") and
      key
      |> String.split(".")
      |> Enum.all?(&Regex.match?(@identifier_segment_pattern, &1))
  end

  defp build_nested([segment], value), do: %{segment => value}
  defp build_nested([segment | rest], value), do: %{segment => build_nested(rest, value)}

  defp deep_merge_with_conflict(map1, map2, strict) do
    Map.merge(map1, map2, &resolve_merge(&1, &2, &3, strict))
  end

  defp resolve_merge(_key, v1, v2, strict) when is_map(v1) and is_map(v2) do
    deep_merge_with_conflict(v1, v2, strict)
  end

  defp resolve_merge(key, v1, v2, strict) when is_map(v1) or is_map(v2) do
    handle_type_conflict(key, v2, strict)
  end

  defp resolve_merge(_key, _v1, v2, _strict), do: v2

  defp handle_type_conflict(key, _v2, true) do
    raise DecodeError,
      message: "Path expansion conflict at key '#{key}': incompatible types",
      reason: :path_conflict
  end

  defp handle_type_conflict(_key, v2, false), do: v2
end
