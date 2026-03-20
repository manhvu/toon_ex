defmodule Toon.UtilsTest do
  use ExUnit.Case, async: true

  alias Toon.Utils

  describe "list?/1" do
    test "returns true for empty list" do
      assert Utils.list?([]) == true
    end

    test "returns true for non-empty list" do
      assert Utils.list?([1, 2, 3]) == true
    end

    test "returns false for non-list values" do
      assert Utils.list?(nil) == false
      assert Utils.list?("string") == false
      assert Utils.list?(42) == false
      assert Utils.list?(%{}) == false
      assert Utils.list?({1, 2}) == false
    end
  end

  describe "same_keys?/1" do
    test "returns true for empty list" do
      assert Utils.same_keys?([]) == true
    end

    test "returns true for single map" do
      assert Utils.same_keys?([%{"a" => 1}]) == true
    end

    test "returns true for maps with same keys" do
      assert Utils.same_keys?([%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]) == true
    end

    test "returns false for maps with different keys" do
      assert Utils.same_keys?([%{"a" => 1}, %{"b" => 2}]) == false
    end

    test "returns false for non-list values" do
      assert Utils.same_keys?(nil) == false
      assert Utils.same_keys?("string") == false
      assert Utils.same_keys?(42) == false
    end

    test "returns false for list starting with non-map" do
      # Exercises the fallback clause: def same_keys?(_), do: false
      assert Utils.same_keys?([1, 2, 3]) == false
    end

    test "returns false for list with map followed by non-maps" do
      # Exercises the Enum.all? logic with is_map check inside
      assert Utils.same_keys?([%{"a" => 1}, 2, 3]) == false
    end
  end

  describe "all_primitives?/1" do
    test "returns true for list of primitives" do
      assert Utils.all_primitives?([1, "a", true, nil, 3.14]) == true
    end

    test "returns false when list contains maps" do
      assert Utils.all_primitives?([1, %{}]) == false
    end

    test "returns false when list contains lists" do
      assert Utils.all_primitives?([1, []]) == false
    end

    test "returns true for empty list" do
      assert Utils.all_primitives?([]) == true
    end
  end

  describe "all_maps?/1" do
    test "returns true for list of maps" do
      assert Utils.all_maps?([%{}, %{"a" => 1}]) == true
    end

    test "returns false when list contains non-maps" do
      assert Utils.all_maps?([%{}, 1]) == false
    end

    test "returns true for empty list" do
      assert Utils.all_maps?([]) == true
    end
  end

  test "negative zero normalizes to integer 0" do
    result = Toon.Utils.normalize(-0.0)
    assert result === 0
    refute is_float(result)
  end
end
