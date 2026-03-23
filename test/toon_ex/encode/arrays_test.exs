defmodule ToonEx.Encode.ArraysTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encode.Arrays

  describe "encode_empty/2" do
    test "encodes empty array with default length_marker" do
      result = Arrays.encode_empty("items")
      assert IO.iodata_to_binary(result) == "items[0]:"
    end

    test "encodes empty array with nil length_marker" do
      result = Arrays.encode_empty("items", nil)
      assert IO.iodata_to_binary(result) == "items[0]:"
    end

    test "encodes empty array with custom length_marker" do
      result = Arrays.encode_empty("items", "#")
      assert IO.iodata_to_binary(result) == "items[#0]:"
    end
  end

  describe "encode_tabular/4 with key_order" do
    test "uses key_order when it matches all keys" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent_string: "  ",
        key_order: ["name", "age"]
      }

      users = [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]

      [header | rows] = Arrays.encode_tabular("users", users, 0, opts)

      assert IO.iodata_to_binary(header) == "users[2]{name,age}:"
      assert Enum.map(rows, &IO.iodata_to_binary/1) == ["Alice,30", "Bob,25"]
    end

    test "falls back to sorted keys when key_order is partial" do
      # key_order doesn't include all keys, so it falls back to alphabetical sort
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: ["name"]}
      users = [%{"name" => "Alice", "age" => 30}]

      [header | _rows] = Arrays.encode_tabular("users", users, 0, opts)

      # Falls back to alphabetical: age, name
      assert IO.iodata_to_binary(header) == "users[1]{age,name}:"
    end

    test "handles empty key_order list" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: []}
      users = [%{"name" => "Alice", "age" => 30}]

      [header | _rows] = Arrays.encode_tabular("users", users, 0, opts)

      # Falls back to alphabetical: age, name
      assert IO.iodata_to_binary(header) == "users[1]{age,name}:"
    end

    test "handles empty list input" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}

      [header] = Arrays.encode_tabular("users", [], 0, opts)

      assert IO.iodata_to_binary(header) == "users[0]{}:"
    end
  end

  describe "encode_list/4 edge cases" do
    test "encodes list with empty object" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [%{}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["-"]
    end

    test "encodes list with nested empty array" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [[]]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["- [0]:"]
    end

    test "encodes list with nested primitive array" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [[1, 2, 3]]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["- [3]: 1,2,3"]
    end
  end
end
