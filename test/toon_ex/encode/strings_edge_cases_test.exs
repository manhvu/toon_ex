defmodule ToonEx.Encode.StringsEdgeCasesTest do
  use ExUnit.Case, async: true
  alias ToonEx.Encode.Strings

  test "key starting with digit must be quoted" do
    result = Strings.encode_key("123abc") |> IO.iodata_to_binary()
    assert result == ~s("123abc")
  end

  test "key with dot is safe (used in path expansion)" do
    assert Strings.safe_key?("user.name") == true
    assert Strings.encode_key("user.name") == "user.name"
  end

  test "key with hyphen must be quoted" do
    result = Strings.encode_key("first-name") |> IO.iodata_to_binary()
    assert result == ~s("first-name")
  end

  test "empty key must be quoted" do
    result = Strings.encode_key("") |> IO.iodata_to_binary()
    assert result == ~s("")
  end

  test "value starting with hyphen must be quoted" do
    # Hyphens start list markers, so unquoted is ambiguous
    assert Strings.safe_unquoted?("-not-a-marker", ",") == false
  end

  test "value that is the string 'null' must be quoted" do
    assert Strings.safe_unquoted?("null", ",") == false
  end

  test "value with pipe delimiter containing pipe must be quoted" do
    assert Strings.safe_unquoted?("a|b", "|") == false
    assert Strings.safe_unquoted?("a|b", ",") == true
  end

  test "value with tab delimiter containing tab must be quoted" do
    assert Strings.safe_unquoted?("a\tb", "\t") == false
  end
end
