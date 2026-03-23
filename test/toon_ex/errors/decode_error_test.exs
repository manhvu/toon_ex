defmodule ToonEx.DecodeErrorTest do
  use ExUnit.Case, async: true

  test "message with only line" do
    err = ToonEx.DecodeError.exception(message: "oops", line: 3)
    assert ToonEx.DecodeError.message(err) == "oops at line 3"
  end

  test "message with line and column" do
    err = ToonEx.DecodeError.exception(message: "oops", line: 3, column: 7)
    assert ToonEx.DecodeError.message(err) == "oops at line 3, column 7"
  end

  test "message with context" do
    err = ToonEx.DecodeError.exception(message: "oops", context: "foo: bar")
    assert ToonEx.DecodeError.message(err) =~ "Context:"
    assert ToonEx.DecodeError.message(err) =~ "foo: bar"
  end

  test "exception/1 from bare string" do
    err = ToonEx.DecodeError.exception("short form")
    assert err.message == "short form"
    assert err.input == nil
  end
end
