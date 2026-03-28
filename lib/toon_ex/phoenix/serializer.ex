defmodule ToonEx.Phoenix.Serializer do
  @moduledoc """
  Satisfies the `PhoenixClient` JSON-parser contract, which requires
  `encode/2`, `encode!/2`, `decode/2`, `decode!/2` and `encode_to_iodata!`.  The optional
  `opts` argument is accepted but intentionally ignored so that this
  module can be dropped in wherever a standard JSON library is expected.
  """

  @type encode_result :: {:ok, binary()} | {:error, term()}
  @type decode_result :: {:ok, term()} | {:error, term()}

  @doc "Encodes `data` with `Toon`. Returns `{:ok, binary}` or `{:error, reason}`."
  @spec encode(term(), keyword()) :: encode_result()
  def encode(data, _opts \\ []) do
    ToonEx.encode(data)
  end

  @doc "Like `encode/2` but raises on failure."
  @spec encode!(term(), keyword()) :: binary()
  def encode!(data, _opts \\ []) do
    ToonEx.encode!(data)
  end

  @doc "Decodes `data` with `Toon`. Returns `{:ok, term}` or `{:error, reason}`."
  @spec decode(binary(), keyword()) :: decode_result()
  def decode(data, _opts \\ []) do
    ToonEx.decode(data)
  end

  @doc "Like `decode/2` but raises on failure."
  @spec decode!(binary(), keyword()) :: term()
  def decode!(data, _opts \\ []) do
    ToonEx.decode!(data)
  end

  def encode_to_iodata!(data) do
    ToonEx.encode_to_iodata!(data)
  end
end
