defmodule ToonEx.FragmentTest do
  use ExUnit.Case, async: true

  describe "Fragment.new/1 with iodata" do
    test "creates fragment from binary string" do
      fragment = ToonEx.Fragment.new("name: Alice")
      assert %ToonEx.Fragment{encode: encode_fn} = fragment
      assert is_function(encode_fn, 1)
    end

    test "creates fragment from iodata list" do
      fragment = ToonEx.Fragment.new(["name: ", "Alice"])
      assert %ToonEx.Fragment{} = fragment
    end

    test "fragment encodes as pre-built iodata" do
      fragment = ToonEx.Fragment.new("name: Alice\nage: 30")
      assert {:ok, "name: Alice\nage: 30"} = ToonEx.encode(fragment)
    end

    test "fragment embedded in a map value" do
      fragment = ToonEx.Fragment.new("name: Alice\nage: 30")
      assert {:ok, result} = ToonEx.encode(%{"user" => fragment})
      assert result == "user:\n  name: Alice\n  age: 30"
    end
  end

  describe "Fragment.new/1 with function" do
    test "creates fragment from encoding function" do
      encode_fn = fn _opts -> "cached: data" end
      fragment = ToonEx.Fragment.new(encode_fn)
      assert %ToonEx.Fragment{} = fragment
    end

    test "function receives options (as a map)" do
      encode_fn = fn opts ->
        delimiter = Map.get(opts, :delimiter, ",")
        "values#{delimiter}a#{delimiter}b"
      end

      fragment = ToonEx.Fragment.new(encode_fn)
      assert {:ok, "values,a,b"} = ToonEx.encode(fragment)
    end

    test "lazy evaluation — function called at encode time" do
      agent = start_link_supervised!({Agent, fn -> 0 end})

      encode_fn = fn _opts ->
        count = Agent.get(agent, & &1)
        Agent.update(agent, &(&1 + 1))
        "count: #{count}"
      end

      fragment = ToonEx.Fragment.new(encode_fn)

      # First encode
      assert {:ok, "count: 0"} = ToonEx.encode(fragment)
      # Second encode — function is called again
      assert {:ok, "count: 1"} = ToonEx.encode(fragment)
    end
  end

  describe "Fragment with encode!" do
    test "works with encode!" do
      fragment = ToonEx.Fragment.new("key: value")
      assert ToonEx.encode!(fragment) == "key: value"
    end

    test "works with encode_to_iodata!" do
      fragment = ToonEx.Fragment.new("key: value")
      iodata = ToonEx.encode_to_iodata!(fragment)
      assert IO.iodata_to_binary(iodata) == "key: value"
    end
  end
end

defmodule ToonEx.HelpersTest do
  use ExUnit.Case, async: true

  require ToonEx.Helpers

  describe "toon_map/1" do
    test "encodes a keyword list to a fragment" do
      fragment = ToonEx.Helpers.toon_map(name: "Alice", age: 30)
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "age: 30\nname: Alice"
    end

    test "keys are sorted alphabetically" do
      fragment = ToonEx.Helpers.toon_map(zebra: 1, apple: 2, middle: 3)
      assert {:ok, result} = ToonEx.encode(fragment)
      # Keys are sorted alphabetically: apple, middle, zebra
      assert result == "apple: 2\nmiddle: 3\nzebra: 1"
    end

    test "handles boolean values" do
      fragment = ToonEx.Helpers.toon_map(active: true, deleted: false)
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "active: true\ndeleted: false"
    end

    test "handles nil values" do
      fragment = ToonEx.Helpers.toon_map(name: nil)
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "name: null"
    end

    test "handles float values" do
      fragment = ToonEx.Helpers.toon_map(score: 3.14)
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "score: 3.14"
    end

    test "handles string values with spaces (unquoted in TOON)" do
      fragment = ToonEx.Helpers.toon_map(greeting: "hello world")
      assert {:ok, result} = ToonEx.encode(fragment)
      # TOON allows spaces in values without quoting
      assert result == "greeting: hello world"
    end

    test "empty keyword list produces empty fragment" do
      fragment = ToonEx.Helpers.toon_map([])
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == ""
    end

    test "single key-value pair" do
      fragment = ToonEx.Helpers.toon_map(count: 42)
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "count: 42"
    end

    test "works with encode!" do
      fragment = ToonEx.Helpers.toon_map(x: 1)
      assert ToonEx.encode!(fragment) == "x: 1"
    end

    test "can be embedded in a larger structure" do
      inner = ToonEx.Helpers.toon_map(name: "Alice", age: 30)
      assert {:ok, result} = ToonEx.encode(%{"user" => inner})
      assert result == "user:\n  age: 30\n  name: Alice"
    end
  end

  describe "toon_map/1 with variable values" do
    test "runtime values are encoded correctly" do
      x = 42
      fragment = ToonEx.Helpers.toon_map(value: x)
      assert {:ok, "value: 42"} = ToonEx.encode(fragment)
    end

    test "multiple runtime values" do
      a = "hello"
      b = 99
      fragment = ToonEx.Helpers.toon_map(a: a, b: b)
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "a: hello\nb: 99"
    end
  end

  describe "toon_map_take/2" do
    test "takes specified keys from a map" do
      map = %{a: 1, b: 2, c: 3}
      fragment = ToonEx.Helpers.toon_map_take(map, [:c, :b])
      assert {:ok, result} = ToonEx.encode(fragment)
      # Keys sorted alphabetically: b, c
      assert result == "b: 2\nc: 3"
    end

    test "handles empty map" do
      map = %{}
      fragment = ToonEx.Helpers.toon_map_take(map, [:a, :b])
      assert {:ok, result} = ToonEx.encode(fragment)
      # Empty map produces empty fragment
      assert result == ""
    end

    test "handles map with missing keys" do
      map = %{a: 1}
      fragment = ToonEx.Helpers.toon_map_take(map, [:a, :b])
      assert {:ok, result} = ToonEx.encode(fragment)
      # Only key 'a' exists, 'b' is nil from Map.get
      assert result == "a: 1\nb: null"
    end

    test "single key" do
      map = %{name: "Alice", age: 30}
      fragment = ToonEx.Helpers.toon_map_take(map, [:name])
      assert {:ok, result} = ToonEx.encode(fragment)
      assert result == "name: Alice"
    end
  end
end
