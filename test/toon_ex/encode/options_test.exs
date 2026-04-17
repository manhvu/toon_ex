defmodule ToonEx.Encode.OptionsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encode.Options

  describe "schema/0" do
    test "returns the options schema with correct structure" do
      schema = Options.schema()

      assert is_list(schema)

      # Validate indent option schema
      assert schema[:indent][:type] == :pos_integer
      assert schema[:indent][:default] == 2

      # Validate delimiter option schema
      assert schema[:delimiter][:type] == :string
      assert schema[:delimiter][:default] == ","

      # Validate length_marker option schema
      assert schema[:length_marker][:type] == {:or, [:string, nil]}
      assert schema[:length_marker][:default] == nil

      # Validate key_order option schema
      assert schema[:key_order][:type] == :any
      assert schema[:key_order][:default] == nil

      # Validate key_folding option schema
      assert schema[:key_folding][:type] == {:in, [:off, :safe]}
      assert schema[:key_folding][:default] == :off

      # Validate flatten_depth option schema
      assert schema[:flatten_depth][:type] == {:or, [:non_neg_integer, {:in, [:infinity]}]}
      assert schema[:flatten_depth][:default] == :infinity
    end
  end

  describe "validate/1" do
    test "returns validated options with defaults" do
      assert {:ok, opts} = Options.validate([])

      assert opts.indent == 2
      assert opts.delimiter == ","
      assert opts.length_marker == nil
      assert opts.indent_string == "  "
    end

    test "accepts valid indent option" do
      assert {:ok, opts} = Options.validate(indent: 4)
      assert opts.indent == 4
      assert opts.indent_string == "    "
    end

    test "accepts minimum valid indent (1)" do
      assert {:ok, opts} = Options.validate(indent: 1)
      assert opts.indent == 1
      assert opts.indent_string == " "
    end

    test "returns error for invalid indent (zero) with descriptive message" do
      assert {:error, error} = Options.validate(indent: 0)
      assert error.key == :indent
      assert error.value == 0
    end

    test "returns error for invalid indent (negative) with descriptive message" do
      assert {:error, error} = Options.validate(indent: -1)
      assert error.key == :indent
      assert error.value == -1
    end

    test "accepts valid delimiter comma" do
      assert {:ok, opts} = Options.validate(delimiter: ",")
      assert opts.delimiter == ","
    end

    test "accepts valid delimiter tab" do
      assert {:ok, opts} = Options.validate(delimiter: "\t")
      assert opts.delimiter == "\t"
    end

    test "accepts valid delimiter pipe" do
      assert {:ok, opts} = Options.validate(delimiter: "|")
      assert opts.delimiter == "|"
    end

    test "returns error for empty string delimiter with descriptive message" do
      assert {:error, error} = Options.validate(delimiter: "")
      assert error.key == :delimiter
      assert error.value == ""
    end

    test "returns error for invalid delimiter with descriptive message" do
      assert {:error, error} = Options.validate(delimiter: ";")
      assert error.key == :delimiter
      assert error.value == ";"
    end

    test "returns error for invalid delimiter (multi-char) with descriptive message" do
      assert {:error, error} = Options.validate(delimiter: ",,")
      assert error.key == :delimiter
      assert error.value == ",,"
    end

    test "accepts valid length_marker" do
      assert {:ok, opts} = Options.validate(length_marker: "#")
      assert opts.length_marker == "#"
    end

    test "accepts nil length_marker" do
      assert {:ok, opts} = Options.validate(length_marker: nil)
      assert opts.length_marker == nil
    end

    test "accepts valid key_order as list" do
      assert {:ok, opts} = Options.validate(key_order: ["name", "age"])
      assert opts.key_order == ["name", "age"]
    end

    test "accepts valid key_folding 'off'" do
      assert {:ok, opts} = Options.validate(key_folding: :off)
      assert opts.key_folding == :off
    end

    test "accepts valid key_folding 'safe'" do
      assert {:ok, opts} = Options.validate(key_folding: :safe)
      assert opts.key_folding == :safe
    end

    test "returns error for invalid key_folding with descriptive message" do
      assert {:error, error} = Options.validate(key_folding: "aggressive")
      assert error.key == :key_folding
      assert error.value == "aggressive"
    end

    test "accepts valid flatten_depth as integer" do
      assert {:ok, opts} = Options.validate(flatten_depth: 3)
      assert opts.flatten_depth == 3
    end

    test "accepts valid flatten_depth as :infinity" do
      assert {:ok, opts} = Options.validate(flatten_depth: :infinity)
      assert opts.flatten_depth == :infinity
    end

    test "returns error for invalid flatten_depth (negative) with descriptive message" do
      assert {:error, error} = Options.validate(flatten_depth: -1)
      assert error.key == :flatten_depth
      assert error.value == -1
    end

    test "returns error for unknown option" do
      assert {:error, %ToonEx.Options.Validator{}} =
               Options.validate(unknown_option: "value")
    end
  end

  describe "validate!/1" do
    test "returns validated options with defaults" do
      opts = Options.validate!([])

      assert opts.indent == 2
      assert opts.delimiter == ","
      assert opts.length_marker == nil
      assert opts.indent_string == "  "
    end

    test "returns validated options with custom values" do
      opts = Options.validate!(indent: 4, delimiter: "\t", length_marker: "#")

      assert opts.indent == 4
      assert opts.delimiter == "\t"
      assert opts.length_marker == "#"
      assert opts.indent_string == "    "
    end

    test "raises ArgumentError for invalid indent" do
      assert_raise ArgumentError, fn ->
        Options.validate!(indent: -1)
      end
    end

    test "raises ArgumentError for invalid delimiter" do
      assert_raise ArgumentError, fn ->
        Options.validate!(delimiter: ";")
      end
    end

    test "raises ArgumentError for invalid key_folding" do
      assert_raise ArgumentError, fn ->
        Options.validate!(key_folding: "aggressive")
      end
    end

    test "raises ArgumentError for unknown option" do
      assert_raise ArgumentError, fn ->
        Options.validate!(foo: "bar")
      end
    end
  end
end
