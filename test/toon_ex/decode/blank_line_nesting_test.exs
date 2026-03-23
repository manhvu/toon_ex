defmodule ToonEx.BlankLineNestingTest do
  use ExUnit.Case, async: true

  test "blank line inside nested block is tolerated in non-strict mode" do
    toon = "parent:\n  a: 1\n\n  b: 2"
    {:ok, result} = ToonEx.decode(toon, strict: false)
    assert result == %{"parent" => %{"a" => 1, "b" => 2}}
  end

  test "blank line inside nested block with sibling after" do
    toon = "parent:\n  a: 1\n\n  b: 2\nsibling: 3"
    {:ok, result} = ToonEx.decode(toon, strict: false)
    assert result["sibling"] == 3
    assert result["parent"]["b"] == 2
  end

  test "multiple consecutive blank lines inside nested block" do
    toon = "parent:\n  a: 1\n\n\n  b: 2"
    {:ok, result} = ToonEx.decode(toon, strict: false)
    assert result == %{"parent" => %{"a" => 1, "b" => 2}}
  end
end
