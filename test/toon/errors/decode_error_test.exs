defmodule Toon.DecodeErrorTest do
  use ExUnit.Case, async: true

  test "message with only line" do
    err = Toon.DecodeError.exception(message: "oops", line: 3)
    assert Toon.DecodeError.message(err) == "oops at line 3"
  end

  test "message with line and column" do
    err = Toon.DecodeError.exception(message: "oops", line: 3, column: 7)
    assert Toon.DecodeError.message(err) == "oops at line 3, column 7"
  end

  test "message with context" do
    err = Toon.DecodeError.exception(message: "oops", context: "foo: bar")
    assert Toon.DecodeError.message(err) =~ "Context:"
    assert Toon.DecodeError.message(err) =~ "foo: bar"
  end

  test "exception/1 from bare string" do
    err = Toon.DecodeError.exception("short form")
    assert err.message == "short form"
    assert err.input == nil
  end
end
