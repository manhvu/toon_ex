defprotocol ToonEx.Encoder do
  @moduledoc """
  Protocol for encoding custom data structures to TOON format.

  This protocol allows you to define how your custom structs should be
  encoded to TOON format, similar to `Jason.Encoder`.

  ## Deriving

  The protocol leverages Elixir's `@derive` feature. Accepted options are:

    * `:only` - encodes only values of specified keys.
    * `:except` - encodes all struct fields except specified keys.

  By default all keys except the `:__struct__` key are encoded.

  The generated implementation pre-computes key encoding at compile time
  for maximum runtime efficiency (inspired by `Jason.Encoder`).

  ## Example

      defmodule User do
        @derive {ToonEx.Encoder, only: [:name, :email]}
        defstruct [:id, :name, :email, :password_hash]
      end

  Or implement the protocol manually:

      defimpl ToonEx.Encoder, for: User do
        def encode(user, opts) do
          %{
            "name" => user.name,
            "email" => user.email
          }
          |> ToonEx.Encode.encode!(opts)
        end
      end
  """

  @fallback_to_any true

  @doc """
  Encodes the given value to TOON format.

  Returns IO data that can be converted to a string.
  """
  @spec encode(t, keyword()) :: iodata() | map()
  def encode(value, opts)
end

defimpl ToonEx.Encoder, for: Any do
  defmacro __deriving__(module, struct, opts) do
    fields = fields_to_encode(struct, opts)

    # Jason-style: pre-compute key strings at compile time.
    # This avoids runtime to_string/1 calls for every encode.
    # The encoder still returns a map (not raw iodata) so that
    # Utils.normalize/1 can recursively normalize nested values.
    key_string_pairs =
      Enum.map(fields, fn field ->
        key_str = to_string(field)
        {field, key_str}
      end)

    # Build a map expression using pre-computed key strings.
    # Equivalent to Map.new(struct, fn {k, v} -> {to_string(k), v} end)
    # but avoids the runtime to_string/1 call per key.
    map_expr =
      Enum.reduce(key_string_pairs, quote(do: %{}), fn {field, key_str}, acc ->
        var = Macro.var(:"__toon_field_#{field}__", __MODULE__)

        quote do
          Map.put(unquote(acc), unquote(key_str), unquote(var))
        end
      end)

    # Destructure fields from struct
    field_destructs =
      Enum.map(fields, fn field ->
        var = Macro.var(:"__toon_field_#{field}__", __MODULE__)
        quote do: unquote(var) = Map.get(struct, unquote(field))
      end)

    quote do
      defimpl ToonEx.Encoder, for: unquote(module) do
        def encode(struct, _opts) do
          unquote_splicing(field_destructs)
          unquote(map_expr)
        end
      end
    end
  end

  def encode(%_{} = struct, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      ToonEx.Encoder protocol must be explicitly implemented for structs.

      You can derive the implementation using:

          @derive {ToonEx.Encoder, only: [...]}
          defstruct ...

      or:

          @derive ToonEx.Encoder
          defstruct ...
      """
  end

  def encode(value, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: value
  end

  defp fields_to_encode(struct, opts) do
    cond do
      only = Keyword.get(opts, :only) ->
        only

      except = Keyword.get(opts, :except) ->
        Map.keys(struct) -- [:__struct__ | except]

      true ->
        Map.keys(struct) -- [:__struct__]
    end
  end
end

defimpl ToonEx.Encoder, for: Atom do
  def encode(nil, _opts), do: "null"
  def encode(true, _opts), do: "true"
  def encode(false, _opts), do: "false"

  def encode(atom, _opts) do
    Atom.to_string(atom)
  end
end

defimpl ToonEx.Encoder, for: BitString do
  def encode(binary, opts) when is_binary(binary) do
    ToonEx.Encode.Strings.encode_string(binary, opts[:delimiter] || ",")
  end
end

defimpl ToonEx.Encoder, for: Integer do
  def encode(integer, _opts) do
    Integer.to_string(integer)
  end
end

defimpl ToonEx.Encoder, for: Float do
  def encode(float, _opts) do
    ToonEx.Encode.Primitives.encode(float, ",")
  end
end

defimpl ToonEx.Encoder, for: List do
  def encode(list, opts) do
    ToonEx.Encode.encode!(list, opts)
  end
end

defimpl ToonEx.Encoder, for: Map do
  def encode(map, opts) do
    # Convert atom keys to strings
    string_map = Map.new(map, fn {k, v} -> {to_string(k), v} end)
    ToonEx.Encode.encode!(string_map, opts)
  end
end

defimpl ToonEx.Encoder, for: ToonEx.Fragment do
  @moduledoc """
  Encoder for `ToonEx.Fragment` — injects pre-encoded TOON iodata
  without re-encoding, avoiding decode/encode round-trips.

  Inspired by `Jason.Encoder` for `Jason.Fragment`.
  """

  def encode(%ToonEx.Fragment{encode: encode_fn}, opts) do
    encode_fn.(opts)
  end
end
