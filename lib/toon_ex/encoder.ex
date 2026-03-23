defprotocol ToonEx.Encoder do
  @moduledoc """
  Protocol for encoding custom data structures to TOON format.

  This protocol allows you to define how your custom structs should be
  encoded to TOON format, similar to `Jason.Encoder`.

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

    quote do
      defimpl ToonEx.Encoder, for: unquote(module) do
        def encode(struct, _opts) do
          struct
          |> Map.take(unquote(fields))
          |> Map.new(fn {k, v} -> {to_string(k), ToonEx.Utils.normalize(v)} end)
        end
      end
    end
  end

  def encode(%_{} = struct, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      Toon.Encoder protocol must be explicitly implemented for structs.

      You can derive the implementation using:

          @derive {Toon.Encoder, only: [...]}
          defstruct ...

      or:

          @derive Toon.Encoder
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
