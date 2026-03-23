defmodule ToonEx.EncoderTest do
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.{
    CustomDate,
    Person,
    StructWithoutEncoder,
    UserWithExcept,
    UserWithOnly
  }

  describe "ToonEx.Encoder for Atom" do
    test "encodes nil" do
      assert ToonEx.Encoder.encode(nil, []) == "null"
    end

    test "encodes true" do
      assert ToonEx.Encoder.encode(true, []) == "true"
    end

    test "encodes false" do
      assert ToonEx.Encoder.encode(false, []) == "false"
    end

    test "encodes regular atom as string" do
      assert ToonEx.Encoder.encode(:hello, []) == "hello"
    end
  end

  describe "ToonEx.Encoder for BitString" do
    test "encodes simple string unchanged" do
      assert ToonEx.Encoder.encode("hello", []) == "hello"
    end

    test "encodes string containing delimiter as iodata with quotes" do
      result = ToonEx.Encoder.encode("a,b", delimiter: ",")
      assert IO.iodata_to_binary(result) == "\"a,b\""
    end
  end

  describe "ToonEx.Encoder for Integer" do
    test "encodes positive integer" do
      assert ToonEx.Encoder.encode(42, []) == "42"
    end

    test "encodes negative integer" do
      assert ToonEx.Encoder.encode(-42, []) == "-42"
    end

    test "encodes zero" do
      assert ToonEx.Encoder.encode(0, []) == "0"
    end
  end

  describe "ToonEx.Encoder for Float" do
    test "encodes float" do
      result = ToonEx.Encoder.encode(3.14, [])
      assert result == "3.14"
    end

    test "encodes negative float" do
      result = ToonEx.Encoder.encode(-3.14, [])
      assert result == "-3.14"
    end
  end

  describe "ToonEx.Encoder for List" do
    test "encodes list via ToonEx.Encode" do
      result = ToonEx.Encoder.encode([1, 2, 3], [])
      assert result == "[3]: 1,2,3"
    end

    test "encodes empty list" do
      result = ToonEx.Encoder.encode([], [])
      assert result == "[0]:"
    end
  end

  describe "ToonEx.Encoder for Map" do
    test "encodes map with atom keys (converted to strings)" do
      result = ToonEx.Encoder.encode(%{name: "Alice"}, [])
      assert result == "name: Alice"
    end

    test "encodes empty map" do
      result = ToonEx.Encoder.encode(%{}, [])
      assert result == ""
    end
  end

  describe "ToonEx.Encoder @derive with except option" do
    test "excludes specified fields from encoding" do
      user = %UserWithExcept{name: "Alice", email: "a@b.com", password: "secret"}
      encoded_map = ToonEx.Encoder.encode(user, [])

      assert Map.has_key?(encoded_map, "name") == true
      assert Map.has_key?(encoded_map, "email") == true
      assert Map.has_key?(encoded_map, "password") == false
    end
  end

  describe "ToonEx.Encoder @derive with only option" do
    test "includes only specified fields" do
      user = %UserWithOnly{name: "Alice", email: "a@b.com", password: "secret"}
      encoded_map = ToonEx.Encoder.encode(user, [])

      assert Map.has_key?(encoded_map, "name") == true
      assert Map.has_key?(encoded_map, "email") == false
      assert Map.has_key?(encoded_map, "password") == false
    end
  end

  describe "ToonEx.Encoder @derive with no options" do
    test "includes all fields except __struct__" do
      person = %Person{name: "Bob", age: 25}
      encoded_map = ToonEx.Encoder.encode(person, [])

      assert encoded_map == %{"name" => "Bob", "age" => 25}
    end
  end

  describe "ToonEx.Encoder explicit implementation" do
    test "uses custom encode function" do
      date = %CustomDate{year: 2024, month: 1, day: 15}
      result = date |> ToonEx.Encoder.encode([]) |> IO.iodata_to_binary()

      assert result == "2024-01-15"
    end
  end

  describe "ToonEx.Encoder for unimplemented types" do
    test "raises Protocol.UndefinedError for struct without implementation" do
      struct = %StructWithoutEncoder{id: 1, value: "test"}

      assert_raise Protocol.UndefinedError,
                   ~r/protocol ToonEx.Encoder not implemented for/,
                   fn ->
                     ToonEx.Encoder.encode(struct, [])
                   end
    end

    test "raises Protocol.UndefinedError for tuple" do
      assert_raise Protocol.UndefinedError, fn ->
        ToonEx.Encoder.encode({1, 2, 3}, [])
      end
    end

    test "raises Protocol.UndefinedError for pid" do
      assert_raise Protocol.UndefinedError, fn ->
        ToonEx.Encoder.encode(self(), [])
      end
    end
  end

  describe "ToonEx.Utils.normalize/1 with structs" do
    test "dispatches to explicit ToonEx.Encoder implementation" do
      date = %CustomDate{year: 2024, month: 1, day: 15}
      assert ToonEx.Utils.normalize(date) == "2024-01-15"
    end

    test "dispatches to @derive ToonEx.Encoder" do
      user = %UserWithExcept{name: "Bob", email: "bob@test.com", password: "secret"}
      assert ToonEx.Utils.normalize(user) == %{"name" => "Bob", "email" => "bob@test.com"}
    end
  end

  # These tests verify the public API accepts structs and atom-keyed maps.
  # The Encoder protocol handles normalization, so the type specs must accept term().
  describe "ToonEx.encode!/1 accepts structs (Dialyzer compatibility)" do
    test "encodes struct with @derive ToonEx.Encoder" do
      person = %Person{name: "Alice", age: 30}
      result = ToonEx.encode!(person)

      assert result =~ "name: Alice"
      assert result =~ "age: 30"
    end

    test "encodes struct with explicit Encoder implementation" do
      date = %CustomDate{year: 2024, month: 6, day: 15}
      result = ToonEx.encode!(date)

      assert result == "2024-06-15"
    end
  end

  describe "ToonEx.encode!/1 accepts maps with atom keys (Dialyzer compatibility)" do
    test "encodes map with atom keys" do
      data = %{name: "Bob", active: true}
      result = ToonEx.encode!(data)

      assert result =~ "name: Bob"
      assert result =~ "active: true"
    end

    test "encodes nested map with atom keys" do
      data = %{user: %{name: "Charlie", age: 25}}
      result = ToonEx.encode!(data)

      assert result =~ "name: Charlie"
    end
  end
end
