defmodule Toon.EdgeCasesTest do
  @moduledoc """
  Tests for edge cases not covered by the main roundtrip suite:
  escape sequences, unicode, boundary values, large inputs, decode+encode symmetry.
  """
  use ExUnit.Case, async: true

  # ── escape sequences ─────────────────────────────────────────────────────────

  describe "escape sequences — roundtrip" do
    for {name, value} <- [
          {"backslash", "\\"},
          {"double-quote", "\""},
          {"newline", "\n"},
          {"carriage return", "\r"},
          {"tab", "\t"},
          {"backslash+quote", "\\\""},
          {"multiple escapes", "a\\b\nc\td"},
          {"only backslashes", "\\\\\\\\"}
        ] do
      @value value
      test "roundtrip: #{name}" do
        enc = Toon.encode!(%{"s" => @value})
        {:ok, dec} = Toon.decode(enc)
        assert dec["s"] == @value
      end
    end
  end

  # ── unicode ───────────────────────────────────────────────────────────────────

  describe "unicode strings" do
    test "ASCII-only value" do
      assert {:ok, %{"x" => "hello"}} = Toon.decode("x: hello")
    end

    test "unicode value round-trips when quoted" do
      enc = Toon.encode!(%{"x" => "héllo"})
      {:ok, dec} = Toon.decode(enc)
      assert dec["x"] == "héllo"
    end

    test "CJK characters round-trip" do
      enc = Toon.encode!(%{"x" => "日本語"})
      {:ok, dec} = Toon.decode(enc)
      assert dec["x"] == "日本語"
    end

    test "emoji round-trip" do
      enc = Toon.encode!(%{"x" => "🎉"})
      {:ok, dec} = Toon.decode(enc)
      assert dec["x"] == "🎉"
    end

    test "unicode key round-trips when quoted" do
      enc = Toon.encode!(%{"名前" => "Alice"})
      {:ok, dec} = Toon.decode(enc)
      assert dec["名前"] == "Alice"
    end
  end

  # ── number boundary values ────────────────────────────────────────────────────

  describe "number boundaries" do
    test "max safe integer round-trips" do
      # 2^53 - 1
      assert {:ok, %{"n" => 9_007_199_254_740_991}} =
               Toon.decode("n: 9007199254740991")
    end

    test "very small positive float" do
      {:ok, r} = Toon.decode("x: 1.0e-15")
      assert_in_delta r["x"], 1.0e-15, 1.0e-25
    end

    test "float encode/decode preserves value" do
      value = 1.0 / 3.0
      enc = Toon.encode!(%{"x" => value})
      {:ok, dec} = Toon.decode(enc)
      assert_in_delta dec["x"], value, 1.0e-14
    end

    # Infinity cannot be constructed via arithmetic on all BEAM versions —
    # float overflow raises badarith rather than producing :infinity.
    # The is_finite guard in Utils (abs > 1.0e308) is covered by the
    # normalize tests; we only verify the max finite value here.
    test "max representable float encodes to a value, not null" do
      result = Toon.encode!(%{"x" => 1.0e308})
      refute result == "x: null"
    end
  end

  # ── large documents ───────────────────────────────────────────────────────────

  describe "large documents" do
    test "map with 200 keys round-trips" do
      data = for i <- 1..200, into: %{}, do: {"key_#{i}", i}
      enc = Toon.encode!(data)
      {:ok, dec} = Toon.decode(enc)
      assert dec == data
    end

    test "tabular array with 500 rows round-trips" do
      data = for i <- 1..500, do: %{"id" => i, "name" => "item_#{i}"}
      enc = Toon.encode!(data)
      {:ok, dec} = Toon.decode(enc)
      assert length(dec) == 500
      assert hd(dec)["id"] == 1
      assert List.last(dec)["id"] == 500
    end

    test "list with 100 elements round-trips" do
      data = Enum.to_list(1..100)
      enc = Toon.encode!(data)
      {:ok, dec} = Toon.decode(enc)
      assert dec == data
    end

    test "deeply nested object 10 levels" do
      data =
        Enum.reduce(1..10, %{"leaf" => "val"}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      enc = Toon.encode!(data)
      {:ok, dec} = Toon.decode(enc)
      assert dec == Toon.Utils.normalize(data)
    end
  end

  # ── blank-line handling ───────────────────────────────────────────────────────

  describe "blank lines" do
    test "trailing blank lines are ignored" do
      assert {:ok, %{"x" => 1}} = Toon.decode("x: 1\n\n\n")
    end

    test "leading blank lines produce empty map" do
      assert {:ok, %{}} = Toon.decode("\n\n")
    end

    test "blank line between top-level keys is tolerated" do
      {:ok, r} = Toon.decode("a: 1\n\nb: 2")
      assert r == %{"a" => 1, "b" => 2}
    end

    test "blank line inside nested object non-strict" do
      {:ok, r} = Toon.decode("parent:\n  a: 1\n\n  b: 2", strict: false)
      assert r["parent"] == %{"a" => 1, "b" => 2}
    end

    test "blank line after nested object, sibling follows" do
      {:ok, r} = Toon.decode("parent:\n  a: 1\n\nsibling: 99", strict: false)
      assert r["sibling"] == 99
      assert r["parent"] == %{"a" => 1}
    end

    test "multiple consecutive blank lines inside nested non-strict" do
      {:ok, r} = Toon.decode("parent:\n  a: 1\n\n\n\n  b: 2", strict: false)
      assert r["parent"] == %{"a" => 1, "b" => 2}
    end
  end

  # ── key_order option ──────────────────────────────────────────────────────────

  describe "key_order encoding option" do
    test "key_order list controls output order" do
      data = %{"z" => 1, "a" => 2, "m" => 3}
      result = Toon.encode!(data, key_order: ["m", "a", "z"])
      assert result == "m: 3\na: 2\nz: 1"
    end

    test "partial key_order falls back to alphabetical" do
      data = %{"z" => 1, "a" => 2}
      # missing "a"
      result = Toon.encode!(data, key_order: ["z"])
      assert result == "a: 2\nz: 1"
    end

    test "key_order does not affect decode" do
      {:ok, r} = Toon.decode("z: 1\na: 2")
      assert Map.keys(r) |> Enum.sort() == ["a", "z"]
    end

    test "tabular array uses key_order for column order" do
      data = [%{"z" => 1, "a" => 2}]
      result = Toon.encode!(data, key_order: ["z", "a"])
      assert result =~ "{z,a}:"
    end
  end

  # ── length_marker option ──────────────────────────────────────────────────────

  describe "length_marker encoding option" do
    test "length_marker prefix is added to array header" do
      {:ok, r} = Toon.encode(%{"x" => [1, 2]}, length_marker: "#")
      assert r == "x[#2]: 1,2"
    end

    test "length_marker prefix added to tabular array" do
      data = [%{"a" => 1}]
      {:ok, r} = Toon.encode(%{"rows" => data}, length_marker: "#")
      assert r =~ "[#1]{"
    end

    test "length_marker prefix added to empty array" do
      {:ok, r} = Toon.encode(%{"x" => []}, length_marker: "#")
      assert r == "x[#0]:"
    end

    # length_marker is an encoder-only decoration. The standard decoder does
    # not accept the # prefix inside []; encode and decode are not symmetric
    # when this option is used.
  end

  # ── Toon.encode! / Toon.decode! error propagation ────────────────────────────

  describe "bang function error propagation" do
    test "decode! raises DecodeError on invalid input" do
      assert_raise Toon.DecodeError, fn -> Toon.decode!("x[3]: a,b") end
    end

    # encode! wraps option errors as Toon.EncodeError, not ArgumentError.
    # (ArgumentError is only raised by validate!/1 when called directly.)
    test "encode! raises Toon.EncodeError on invalid options" do
      assert_raise Toon.EncodeError, fn -> Toon.encode!(%{}, indent: 0) end
    end

    test "decode! returns value directly on success" do
      assert Toon.decode!("x: 1") == %{"x" => 1}
    end

    test "encode! returns string directly on success" do
      assert Toon.encode!(%{"x" => 1}) == "x: 1"
    end
  end

  # ── decode then encode identity ───────────────────────────────────────────────

  describe "decode → encode → decode identity" do
    @samples [
      "name: Alice\nage: 30",
      "tags[3]: a,b,c",
      "rows[2]{x,y}:\n  1,2\n  3,4",
      "items[2]:\n  - a: 1\n  - b: 2"
    ]

    for toon <- @samples do
      @toon toon
      test "decode→encode→decode: #{String.replace(@toon, "\n", "↵")}" do
        {:ok, d1} = Toon.decode(@toon)
        enc = Toon.encode!(d1)
        {:ok, d2} = Toon.decode(enc)
        assert d1 == d2
      end
    end
  end
end
