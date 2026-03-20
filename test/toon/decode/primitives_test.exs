defmodule Toon.Decode.PrimitivesTest do
  use ExUnit.Case, async: true

  # ── null ────────────────────────────────────────────────────────────────────

  describe "null" do
    test "root null" do
      assert {:ok, nil} = Toon.decode("null")
    end

    test "null as map value" do
      assert {:ok, %{"x" => nil}} = Toon.decode("x: null")
    end

    test "null in inline array" do
      assert {:ok, %{"a" => [nil, nil]}} = Toon.decode("a[2]: null,null")
    end

    test "null is case-sensitive — 'Null' is a string" do
      assert {:ok, %{"x" => "Null"}} = Toon.decode("x: Null")
    end

    test "null is case-sensitive — 'NULL' is a string" do
      assert {:ok, %{"x" => "NULL"}} = Toon.decode("x: NULL")
    end
  end

  # ── booleans ────────────────────────────────────────────────────────────────

  describe "booleans" do
    test "true as map value" do
      assert {:ok, %{"x" => true}} = Toon.decode("x: true")
    end

    test "false as map value" do
      assert {:ok, %{"x" => false}} = Toon.decode("x: false")
    end

    test "root true" do
      assert {:ok, true} = Toon.decode("true")
    end

    test "root false" do
      assert {:ok, false} = Toon.decode("false")
    end

    test "True is a string (case-sensitive)" do
      assert {:ok, %{"x" => "True"}} = Toon.decode("x: True")
    end

    test "TRUE is a string" do
      assert {:ok, %{"x" => "TRUE"}} = Toon.decode("x: TRUE")
    end

    test "booleans in inline array" do
      assert {:ok, %{"flags" => [true, false, true]}} = Toon.decode("flags[3]: true,false,true")
    end
  end

  # ── integers ────────────────────────────────────────────────────────────────

  describe "integers" do
    test "zero" do
      assert {:ok, %{"n" => 0}} = Toon.decode("n: 0")
    end

    test "positive integer" do
      assert {:ok, %{"n" => 42}} = Toon.decode("n: 42")
    end

    test "negative integer" do
      assert {:ok, %{"n" => -17}} = Toon.decode("n: -17")
    end

    test "large integer" do
      assert {:ok, %{"n" => 1_000_000}} = Toon.decode("n: 1000000")
    end

    test "negative zero is integer 0" do
      assert {:ok, %{"n" => 0}} = Toon.decode("n: -0")
    end

    test "leading zero makes it a string" do
      assert {:ok, %{"n" => "05"}} = Toon.decode("n: 05")
    end

    test "leading zeros with minus makes it a string" do
      assert {:ok, %{"n" => "-007"}} = Toon.decode("n: -007")
    end

    test "single zero is integer, not string" do
      {:ok, result} = Toon.decode("n: 0")
      assert result["n"] === 0
      assert is_integer(result["n"])
    end

    test "root integer" do
      assert {:ok, 99} = Toon.decode("99")
    end
  end

  # ── floats ──────────────────────────────────────────────────────────────────

  describe "floats" do
    test "basic float" do
      assert {:ok, %{"x" => 3.14}} = Toon.decode("x: 3.14")
    end

    test "negative float" do
      assert {:ok, %{"x" => -2.5}} = Toon.decode("x: -2.5")
    end

    test "float with trailing zero decodes as integer (whole floats have no decimal)" do
      # TOON encodes 1.0 as "1" (no decimal point for whole-number floats).
      # "1" decodes back as integer 1, not float 1.0.
      assert {:ok, %{"x" => 1}} = Toon.decode("x: 1.0")
      {:ok, r} = Toon.decode("x: 1.0")
      assert is_integer(r["x"])
    end

    test "scientific notation lowercase e" do
      assert {:ok, %{"x" => 1_000_000}} = Toon.decode("x: 1e6")
    end

    test "scientific notation uppercase E" do
      assert {:ok, %{"x" => 1_000_000}} = Toon.decode("x: 1E6")
    end

    test "scientific notation with positive exponent sign" do
      assert {:ok, %{"x" => 1_000}} = Toon.decode("x: 1E+03")
    end

    test "scientific notation with negative exponent" do
      {:ok, result} = Toon.decode("x: 2.5e-2")
      assert_in_delta result["x"], 0.025, 1.0e-15
    end

    test "root float" do
      assert {:ok, 1.5} = Toon.decode("1.5")
    end
  end

  # ── strings ─────────────────────────────────────────────────────────────────

  describe "unquoted strings" do
    test "simple word" do
      assert {:ok, %{"name" => "Alice"}} = Toon.decode("name: Alice")
    end

    test "string with hyphen" do
      assert {:ok, %{"slug" => "hello-world"}} = Toon.decode("slug: hello-world")
    end

    test "string with dot" do
      assert {:ok, %{"v" => "1.2.3"}} = Toon.decode("v: 1.2.3")
    end

    test "root string" do
      assert {:ok, "hello"} = Toon.decode("hello")
    end
  end

  describe "quoted strings" do
    test "empty quoted string" do
      assert {:ok, %{"s" => ""}} = Toon.decode(~s(s: ""))
    end

    test "quoted string with spaces" do
      assert {:ok, %{"s" => "hello world"}} = Toon.decode(~s(s: "hello world"))
    end

    test "escape: backslash" do
      assert {:ok, %{"s" => "\\"}} = Toon.decode(~s(s: "\\\\"))
    end

    test "escape: double-quote" do
      assert {:ok, %{"s" => "\""}} = Toon.decode(~s(s: "\\""))
    end

    test "escape: newline \\n" do
      assert {:ok, %{"s" => "\n"}} = Toon.decode(~s(s: "\\n"))
    end

    test "escape: carriage return \\r" do
      assert {:ok, %{"s" => "\r"}} = Toon.decode(~s(s: "\\r"))
    end

    test "escape: tab \\t" do
      assert {:ok, %{"s" => "\t"}} = Toon.decode(~s(s: "\\t"))
    end

    test "multiple escapes in one string" do
      assert {:ok, %{"s" => "a\nb\tc"}} = Toon.decode(~s(s: "a\\nb\\tc"))
    end

    test "invalid escape sequence raises" do
      assert_raise Toon.DecodeError, fn -> Toon.decode!(~s(s: "\\q")) end
    end

    test "unterminated quoted string raises" do
      assert_raise Toon.DecodeError, fn -> Toon.decode!(~s(s: "no end)) end
    end

    test "quoted string that looks like null is a string" do
      assert {:ok, %{"s" => "null"}} = Toon.decode(~s(s: "null"))
    end

    test "quoted string that looks like true is a string" do
      assert {:ok, %{"s" => "true"}} = Toon.decode(~s(s: "true"))
    end

    test "quoted string that looks like an integer is a string" do
      assert {:ok, %{"s" => "42"}} = Toon.decode(~s(s: "42"))
    end

    test "quoted string preserving leading/trailing spaces" do
      assert {:ok, %{"s" => " padded "}} = Toon.decode(~s(s: " padded "))
    end
  end
end
