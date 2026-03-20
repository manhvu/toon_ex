defmodule Toon.Decode.PathExpansionTest do
  use ExUnit.Case, async: true

  # ── off (default) ────────────────────────────────────────────────────────────

  describe "expand_paths: off (default)" do
    test "dotted key is preserved as literal" do
      {:ok, r} = Toon.decode("user.name: Ada")
      assert r == %{"user.name" => "Ada"}
    end

    test "multiple dotted keys are separate literal keys" do
      {:ok, r} = Toon.decode("a.b: 1\na.c: 2")
      assert r == %{"a.b" => 1, "a.c" => 2}
    end
  end

  # ── safe — single key expansion ──────────────────────────────────────────────

  describe "expand_paths: safe — basic expansion" do
    test "one-level dot expands to two-level map" do
      {:ok, r} = Toon.decode("a.b: 1", expand_paths: "safe")
      assert r == %{"a" => %{"b" => 1}}
    end

    test "two-level dot expands to three-level map" do
      {:ok, r} = Toon.decode("a.b.c: 1", expand_paths: "safe")
      assert r == %{"a" => %{"b" => %{"c" => 1}}}
    end

    test "five-level dot chain" do
      {:ok, r} = Toon.decode("a.b.c.d.e: 1", expand_paths: "safe")
      assert r == %{"a" => %{"b" => %{"c" => %{"d" => %{"e" => 1}}}}}
    end

    test "single-segment key (no dot) is never expanded" do
      {:ok, r} = Toon.decode("name: Alice", expand_paths: "safe")
      assert r == %{"name" => "Alice"}
    end

    test "segment starting with digit prevents expansion" do
      {:ok, r} = Toon.decode("1abc.x: 1", expand_paths: "safe")
      assert r == %{"1abc.x" => 1}
    end

    test "segment with hyphen prevents expansion" do
      {:ok, r} = Toon.decode("full-name.x: 1", expand_paths: "safe")
      assert r == %{"full-name.x" => 1}
    end

    test "segment with space prevents expansion" do
      {:ok, r} = Toon.decode(~s("a b.c": 1), expand_paths: "safe")
      assert r == %{"a b.c" => 1}
    end
  end

  # ── safe — quoted-key exemption ───────────────────────────────────────────────

  describe "expand_paths: safe — quoted keys are never expanded" do
    test "quoted dotted key is preserved as literal" do
      {:ok, r} = Toon.decode(~s("a.b": 1), expand_paths: "safe")
      assert r == %{"a.b" => 1}
    end

    test "mix of quoted and unquoted dotted keys" do
      {:ok, r} = Toon.decode("a.b: 1\n\"c.d\": 2", expand_paths: "safe")
      assert r == %{"a" => %{"b" => 1}, "c.d" => 2}
    end
  end

  # ── safe — deep merge ────────────────────────────────────────────────────────

  describe "expand_paths: safe — deep merge" do
    test "two paths sharing a prefix are merged" do
      {:ok, r} = Toon.decode("a.b: 1\na.c: 2", expand_paths: "safe")
      assert r == %{"a" => %{"b" => 1, "c" => 2}}
    end

    test "three paths sharing a prefix are merged" do
      {:ok, r} = Toon.decode("a.b.x: 1\na.b.y: 2\na.c: 3", expand_paths: "safe")
      assert r == %{"a" => %{"b" => %{"x" => 1, "y" => 2}, "c" => 3}}
    end

    test "path and non-dotted key coexist" do
      {:ok, r} = Toon.decode("a.b: 1\nz: 99", expand_paths: "safe")
      assert r == %{"a" => %{"b" => 1}, "z" => 99}
    end
  end

  # ── safe — with array values ──────────────────────────────────────────────────

  describe "expand_paths: safe — array values" do
    test "inline array under dotted path" do
      {:ok, r} = Toon.decode("x.items[2]: a,b", expand_paths: "safe")
      assert r == %{"x" => %{"items" => ["a", "b"]}}
    end

    test "tabular array under dotted path" do
      toon = "a.b.items[2]{id,name}:\n  1,A\n  2,B"
      {:ok, r} = Toon.decode(toon, expand_paths: "safe")

      assert r == %{
               "a" => %{
                 "b" => %{"items" => [%{"id" => 1, "name" => "A"}, %{"id" => 2, "name" => "B"}]}
               }
             }
    end

    test "empty array under dotted path" do
      {:ok, r} = Toon.decode("a.b[0]:", expand_paths: "safe")
      assert r == %{"a" => %{"b" => []}}
    end
  end

  # ── safe — conflict handling (strict: true) ───────────────────────────────────

  describe "expand_paths: safe — conflicts (strict: true)" do
    test "duplicate expansion target raises" do
      # a.b: 1  expands to {a: {b: 1}}, then a: 2 conflicts
      assert_raise Toon.DecodeError, fn ->
        Toon.decode!("a.b: 1\na: 2", expand_paths: "safe", strict: true)
      end
    end

    test "incompatible types at merge point raises" do
      # a: 1 is a primitive; a.b: 2 would require a to be a map
      assert_raise Toon.DecodeError, fn ->
        Toon.decode!("a: 1\na.b: 2", expand_paths: "safe", strict: true)
      end
    end
  end

  # ── safe — conflict handling (strict: false, LWW) ────────────────────────────

  describe "expand_paths: safe — last-write-wins (strict: false)" do
    test "primitive overwrites expanded object" do
      {:ok, r} = Toon.decode("a.b: 1\na: 2", expand_paths: "safe", strict: false)
      assert r == %{"a" => 2}
    end

    test "expanded object overwrites primitive" do
      {:ok, r} = Toon.decode("a: 1\na.b: 2", expand_paths: "safe", strict: false)
      assert r == %{"a" => %{"b" => 2}}
    end
  end
end
