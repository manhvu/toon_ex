defmodule ToonEx.Decode.OptionsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Decode.Options

  describe "schema/0" do
    test "returns the options schema with correct structure" do
      schema = Options.schema()

      assert is_list(schema)

      # Validate keys option schema
      assert schema[:keys][:type] == {:in, [:strings, :atoms, :atoms!]}
      assert schema[:keys][:default] == :strings

      # Validate strict option schema
      assert schema[:strict][:type] == :boolean
      assert schema[:strict][:default] == true

      # Validate indent_size option schema
      assert schema[:indent_size][:type] == :pos_integer
      assert schema[:indent_size][:default] == 2

      # Validate expand_paths option schema
      assert schema[:expand_paths][:type] == {:in, [:off, :safe]}
      assert schema[:expand_paths][:default] == :off
    end
  end

  describe "validate/1" do
    test "returns validated options with defaults" do
      assert {:ok, opts} = Options.validate([])

      assert opts.keys == :strings
      assert opts.strict == true
      assert opts.indent_size == 2
      assert opts.expand_paths == :off
    end

    test "accepts valid keys option :strings" do
      assert {:ok, opts} = Options.validate(keys: :strings)
      assert opts.keys == :strings
    end

    test "accepts valid keys option :atoms" do
      assert {:ok, opts} = Options.validate(keys: :atoms)
      assert opts.keys == :atoms
    end

    test "accepts valid keys option :atoms!" do
      assert {:ok, opts} = Options.validate(keys: :atoms!)
      assert opts.keys == :atoms!
    end

    test "returns error for invalid keys option with descriptive message" do
      assert {:error, error} = Options.validate(keys: :invalid)
      assert error.key == :keys
      assert error.value == :invalid
    end

    test "accepts valid strict option" do
      assert {:ok, opts} = Options.validate(strict: false)
      assert opts.strict == false
    end

    test "returns error for invalid strict option with descriptive message" do
      assert {:error, error} = Options.validate(strict: "yes")
      assert error.key == :strict
      assert error.value == "yes"
    end

    test "accepts valid indent_size option" do
      assert {:ok, opts} = Options.validate(indent_size: 4)
      assert opts.indent_size == 4
    end

    test "accepts minimum valid indent_size (1)" do
      assert {:ok, opts} = Options.validate(indent_size: 1)
      assert opts.indent_size == 1
    end

    test "returns error for invalid indent_size (zero) with descriptive message" do
      assert {:error, error} = Options.validate(indent_size: 0)
      assert error.key == :indent_size
      assert error.value == 0
    end

    test "returns error for invalid indent_size (negative) with descriptive message" do
      assert {:error, error} = Options.validate(indent_size: -1)
      assert error.key == :indent_size
      assert error.value == -1
    end

    test "accepts valid expand_paths option 'off'" do
      assert {:ok, opts} = Options.validate(expand_paths: :off)
      assert opts.expand_paths == :off
    end

    test "accepts valid expand_paths option 'safe'" do
      assert {:ok, opts} = Options.validate(expand_paths: :safe)
      assert opts.expand_paths == :safe
    end

    test "returns error for invalid expand_paths option" do
      assert {:error, %ToonEx.Options.Validator{key: :expand_paths}} =
               Options.validate(expand_paths: "invalid")
    end

    test "returns error for unknown option" do
      assert {:error, %ToonEx.Options.Validator{}} =
               Options.validate(unknown_option: "value")
    end
  end

  describe "validate!/1" do
    test "returns validated options with defaults" do
      opts = Options.validate!([])

      assert opts.keys == :strings
      assert opts.strict == true
      assert opts.indent_size == 2
    end

    test "returns validated options with custom values" do
      opts = Options.validate!(keys: :atoms, strict: false, indent_size: 4)

      assert opts.keys == :atoms
      assert opts.strict == false
      assert opts.indent_size == 4
    end

    test "raises ArgumentError for invalid keys option" do
      assert_raise ArgumentError, fn ->
        Options.validate!(keys: :invalid)
      end
    end

    test "raises ArgumentError for invalid indent_size" do
      assert_raise ArgumentError, fn ->
        Options.validate!(indent_size: -1)
      end
    end

    test "raises ArgumentError for invalid expand_paths" do
      assert_raise ArgumentError, fn ->
        Options.validate!(expand_paths: "aggressive")
      end
    end

    test "raises ArgumentError for unknown option" do
      assert_raise ArgumentError, fn ->
        Options.validate!(foo: "bar")
      end
    end
  end
end
