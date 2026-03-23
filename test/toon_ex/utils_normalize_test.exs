defmodule ToonEx.Utils.NormalizeTest do
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.{Company, CustomDate, Person, UserWithExcept}
  alias ToonEx.Utils

  describe "normalize/1" do
    test "nil" do
      assert Utils.normalize(nil) == nil
    end

    test "boolean" do
      assert Utils.normalize(true) == true
      assert Utils.normalize(false) == false
    end

    test "string" do
      assert Utils.normalize("hello") == "hello"
    end

    test "atom converts to string" do
      assert Utils.normalize(:ok) == "ok"
      assert Utils.normalize(:less_than_or_equal) == "less_than_or_equal"
    end

    test "integer" do
      assert Utils.normalize(42) == 42
    end

    test "float" do
      assert Utils.normalize(3.14) == 3.14
    end

    test "negative zero normalizes to 0" do
      assert Utils.normalize(-0.0) == 0
    end

    test "list recursively normalizes" do
      assert Utils.normalize([:a, :b]) == ["a", "b"]
    end

    test "map converts atom keys and values" do
      assert Utils.normalize(%{status: :active}) == %{"status" => "active"}
    end

    test "unsupported types normalize to nil" do
      assert Utils.normalize({1, 2}) == nil
      assert Utils.normalize(self()) == nil
    end

    test "three-level nested structure with atoms" do
      input = %{
        level1: %{
          level2: %{
            level3: :deep_atom,
            items: [:a, :b]
          },
          status: :pending
        },
        top: :value
      }

      expected = %{
        "level1" => %{
          "level2" => %{
            "level3" => "deep_atom",
            "items" => ["a", "b"]
          },
          "status" => "pending"
        },
        "top" => "value"
      }

      assert Utils.normalize(input) == expected
    end

    test "struct with @derive normalizes to map" do
      person = %Person{name: "Alice", age: 30}
      assert Utils.normalize(person) == %{"name" => "Alice", "age" => 30}
    end

    test "nested struct normalizes recursively" do
      company = %Company{name: "Acme", ceo: %Person{name: "Bob", age: 45}}
      expected = %{"name" => "Acme", "ceo" => %{"name" => "Bob", "age" => 45}}
      assert Utils.normalize(company) == expected
    end

    test "struct with except option excludes fields" do
      user = %UserWithExcept{name: "Alice", email: "a@b.com", password: "secret"}
      assert Utils.normalize(user) == %{"name" => "Alice", "email" => "a@b.com"}
    end

    test "struct with explicit encoder normalizes to its return value" do
      date = %CustomDate{year: 2024, month: 1, day: 15}
      assert Utils.normalize(date) == "2024-01-15"
    end
  end
end
