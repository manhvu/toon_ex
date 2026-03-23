defmodule ToonEx.StrictModeTest do
  use ExUnit.Case, async: true

  test "tab in indentation raises in strict mode" do
    toon = "parent:\n\tchild: 1"

    assert_raise ToonEx.DecodeError, ~r/Tab/, fn ->
      ToonEx.decode!(toon, strict: true)
    end
  end

  test "non-multiple-of-indent_size indentation raises in strict mode" do
    # 3 spaces with indent_size: 2
    toon = "parent:\n   child: 1"

    assert_raise ToonEx.DecodeError, fn ->
      ToonEx.decode!(toon, strict: true, indent_size: 2)
    end
  end

  test "non-multiple indentation is accepted in non-strict mode" do
    toon = "parent:\n   child: 1"
    {:ok, result} = ToonEx.decode(toon, strict: false)
    assert result["parent"]["child"] == 1
  end

  test "blank lines inside tabular array raise in strict mode" do
    toon = "rows[2]{a,b}:\n  1,2\n\n  3,4"

    assert_raise ToonEx.DecodeError, fn ->
      ToonEx.decode!(toon, strict: true)
    end
  end
end
