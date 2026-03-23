defmodule ToonEx.JSON do
  @moduledoc """
  Transforms between JSON and TOON format.

  Simply using Elixir JSON to transforms between JSON and TOON.

  Example:

  ```elixir
  text =
  "[4]:
    - 1
    - 2
    - hello
    - test:
        k1: 1"

  json = ToonEx.JSON.from_toon!(text)
  # "[1, 2, "hello ", {"test": {"k1": 1}}]"
  ```

  """

  @spec to_toon(binary()) :: {:ok, binary()} | {:error, term()}
  def to_toon(json) when is_binary(json) do
    with {:ok, term} <- JSON.decode(json) do
      ToonEx.encode(term)
    end
  end

  @spec to_toon(binary()) :: binary()
  def to_toon!(json) when is_binary(json) do
    term = JSON.decode!(json)
    ToonEx.encode!(term)
  end

  @spec from_toon(binary()) :: {:ok, binary()} | {:error, term()}
  def from_toon(toon) when is_binary(toon) do
    with {:ok, term} <- ToonEx.decode(toon) do
      try do
        {:ok, JSON.encode!(term)}
      catch
        {:error, _reason} = error -> error
        other -> {:error, other}
      end
    end
  end

  @spec from_toon!(binary()) :: binary()
  def from_toon!(toon) when is_binary(toon) do
    term = ToonEx.decode!(toon)
    JSON.encode!(term)
  end
end
