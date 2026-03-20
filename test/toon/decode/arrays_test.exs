defmodule Toon.Decode.ArraysTest do
  use ExUnit.Case, async: true

  # ── inline arrays (key[N]: v1,v2) ───────────────────────────────────────────

  describe "inline arrays — comma delimiter" do
    test "empty inline array" do
      assert {:ok, %{"x" => []}} = Toon.decode("x[0]:")
    end

    test "single-element array" do
      assert {:ok, %{"x" => ["a"]}} = Toon.decode("x[1]: a")
    end

    test "multi-element primitive array" do
      assert {:ok, %{"tags" => ["a", "b", "c"]}} = Toon.decode("tags[3]: a,b,c")
    end

    test "integer array" do
      assert {:ok, %{"ns" => [1, 2, 3]}} = Toon.decode("ns[3]: 1,2,3")
    end

    test "mixed-type array" do
      assert {:ok, %{"x" => [1, "hello", true, nil]}} =
               Toon.decode("x[4]: 1,hello,true,null")
    end

    test "array with empty tokens" do
      assert {:ok, %{"x" => ["a", "", "c"]}} = Toon.decode("x[3]: a,,c")
    end

    test "spaces around comma are trimmed" do
      assert {:ok, %{"x" => ["a", "b"]}} = Toon.decode("x[2]: a , b")
    end

    test "length mismatch raises" do
      assert_raise Toon.DecodeError, fn -> Toon.decode!("x[3]: a,b") end
    end

    test "leading zeros in array elements are strings" do
      assert {:ok, %{"codes" => ["007", "042"]}} = Toon.decode("codes[2]: 007,042")
    end

    test "quoted strings in inline array" do
      assert {:ok, %{"x" => ["hello world", "b"]}} =
               Toon.decode(~s(x[2]: "hello world",b))
    end
  end

  describe "inline arrays — tab delimiter" do
    test "tab-delimited array" do
      assert {:ok, %{"x" => [1, 2, 3]}} = Toon.decode("x[3\t]: 1\t2\t3")
    end

    test "tab delimiter in header marker" do
      {:ok, result} = Toon.decode("x[2\t]: a\tb")
      assert result == %{"x" => ["a", "b"]}
    end
  end

  describe "inline arrays — pipe delimiter" do
    test "pipe-delimited array" do
      assert {:ok, %{"x" => ["a", "b", "c"]}} = Toon.decode("x[3|]: a|b|c")
    end
  end

  # ── tabular arrays (key[N]{fields}: rows) ───────────────────────────────────

  describe "tabular arrays" do
    test "basic tabular array" do
      toon = "users[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, result} = Toon.decode(toon)

      assert result["users"] == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "single-row tabular array" do
      toon = "users[1]{name,age}:\n  Alice,30"
      {:ok, result} = Toon.decode(toon)
      assert result["users"] == [%{"name" => "Alice", "age" => 30}]
    end

    test "tabular with null and boolean values" do
      toon = "rows[1]{a,b,c}:\n  null,true,false"
      {:ok, result} = Toon.decode(toon)
      assert hd(result["rows"]) == %{"a" => nil, "b" => true, "c" => false}
    end

    test "tabular row count mismatch raises" do
      toon = "users[3]{name,age}:\n  Alice,30\n  Bob,25"
      assert_raise Toon.DecodeError, fn -> Toon.decode!(toon) end
    end

    test "tabular column count mismatch raises" do
      toon = "users[1]{name,age}:\n  Alice,30,extra"
      assert_raise Toon.DecodeError, fn -> Toon.decode!(toon) end
    end

    test "tabular with tab delimiter" do
      # Fields in {a,b} are always comma-separated; tab is the row delimiter.
      toon = "rows[1\t]{a,b}:\n  1\t2"
      {:ok, result} = Toon.decode(toon)
      assert result["rows"] == [%{"a" => 1, "b" => 2}]
    end

    test "tabular with pipe delimiter" do
      # Fields in {a,b} are always comma-separated; pipe is the row delimiter.
      toon = "rows[1|]{a,b}:\n  x|y"
      {:ok, result} = Toon.decode(toon)
      assert result["rows"] == [%{"a" => "x", "b" => "y"}]
    end

    test "tabular with quoted field names" do
      toon = ~s(rows[1]{"full name",age}:\n  Alice Liddell,10)
      {:ok, result} = Toon.decode(toon)
      assert [row] = result["rows"]
      assert row["full name"] == "Alice Liddell"
    end

    test "keys: :atoms in tabular array" do
      toon = "rows[1]{name,age}:\n  Alice,30"
      {:ok, result} = Toon.decode(toon, keys: :atoms)
      assert hd(result[:rows]) == %{name: "Alice", age: 30}
    end

    test "blank line inside tabular raises in strict mode" do
      toon = "rows[2]{a,b}:\n  1,2\n\n  3,4"
      assert_raise Toon.DecodeError, fn -> Toon.decode!(toon, strict: true) end
    end
  end

  # ── list arrays (key[N]: with indented items) ───────────────────────────────

  describe "list arrays" do
    test "list of primitives" do
      toon = "items[3]:\n  - 1\n  - 2\n  - 3"
      assert {:ok, %{"items" => [1, 2, 3]}} = Toon.decode(toon)
    end

    test "list of strings" do
      toon = "tags[2]:\n  - elixir\n  - toon"
      assert {:ok, %{"tags" => ["elixir", "toon"]}} = Toon.decode(toon)
    end

    test "list of objects (non-uniform)" do
      toon = "items[2]:\n  - title: Book\n    price: 9\n  - title: Movie\n    duration: 120"
      {:ok, result} = Toon.decode(toon)
      assert length(result["items"]) == 2
      assert hd(result["items"])["title"] == "Book"
      assert hd(result["items"])["price"] == 9
    end

    test "list of uniform objects" do
      toon = "users[2]:\n  - name: Alice\n    age: 30\n  - name: Bob\n    age: 25"
      {:ok, result} = Toon.decode(toon)

      assert result["users"] == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "list with empty object item" do
      toon = "items[1]:\n  -"
      {:ok, result} = Toon.decode(toon)
      assert result["items"] == [%{}]
    end

    test "list length mismatch raises" do
      toon = "items[3]:\n  - a\n  - b"
      assert_raise Toon.DecodeError, fn -> Toon.decode!(toon) end
    end

    test "nested list inside list item" do
      toon = "outer[1]:\n  - tags[2]: a,b"
      {:ok, result} = Toon.decode(toon)
      assert result["outer"] == [%{"tags" => ["a", "b"]}]
    end

    test "list item with nested object" do
      toon = "items[1]:\n  - name: X\n    meta:\n      k: v"
      {:ok, result} = Toon.decode(toon)
      assert hd(result["items"]) == %{"name" => "X", "meta" => %{"k" => "v"}}
    end

    test "blank line inside list array raises in strict mode" do
      toon = "items[2]:\n  - a\n\n  - b"
      assert_raise Toon.DecodeError, fn -> Toon.decode!(toon, strict: true) end
    end
  end

  # ── root-level arrays ────────────────────────────────────────────────────────

  describe "root-level arrays" do
    test "root empty array" do
      assert {:ok, []} = Toon.decode("[0]:")
    end

    test "root inline array of primitives" do
      assert {:ok, [1, 2, 3]} = Toon.decode("[3]: 1,2,3")
    end

    test "root tabular array" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, result} = Toon.decode(toon)

      assert result == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "root list array of primitives" do
      toon = "[3]:\n  - a\n  - b\n  - c"
      assert {:ok, ["a", "b", "c"]} = Toon.decode(toon)
    end

    test "root list array of objects" do
      toon = "[2]:\n  - x: 1\n  - x: 2"
      {:ok, result} = Toon.decode(toon)
      assert result == [%{"x" => 1}, %{"x" => 2}]
    end

    test "root tab-delimited array" do
      assert {:ok, ["a", "b"]} = Toon.decode("[2\t]: a\tb")
    end

    test "root pipe-delimited array" do
      assert {:ok, ["a", "b"]} = Toon.decode("[2|]: a|b")
    end
  end

  # ── nested arrays ────────────────────────────────────────────────────────────

  describe "nested arrays" do
    test "array of arrays (inline)" do
      toon = "[2]:\n  - [2]: 1,2\n  - [2]: 3,4"
      assert {:ok, [[1, 2], [3, 4]]} = Toon.decode(toon)
    end

    test "empty nested array" do
      toon = "[1]:\n  - [0]:"
      assert {:ok, [[]]} = Toon.decode(toon)
    end

    test "deeply nested arrays" do
      toon = "[1]:\n  - [1]:\n    - [1]:\n      - deep"
      assert {:ok, [[["deep"]]]} = Toon.decode(toon)
    end

    test "sibling after nested array" do
      toon = "[2]:\n  - [1]:\n    - inner\n  - outer"
      assert {:ok, [["inner"], "outer"]} = Toon.decode(toon)
    end

    test "mixed empty and non-empty nested arrays" do
      toon = "[3]:\n  - [0]:\n  - [1]:\n    - 42\n  - [0]:"
      assert {:ok, [[], [42], []]} = Toon.decode(toon)
    end
  end
end
