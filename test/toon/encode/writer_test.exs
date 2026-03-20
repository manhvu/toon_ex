defmodule Toon.Encode.WriterTest do
  use ExUnit.Case, async: true
  alias Toon.Encode.Writer

  test "new/1 sets correct indent string" do
    assert Writer.new(4).indent_string == "    "
  end

  test "push/3 at depth 0 adds no indentation" do
    w = Writer.new(2) |> Writer.push("key: val", 0)
    assert Writer.to_string(w) == "key: val"
  end

  test "push/3 at depth 2 adds two indent levels" do
    w = Writer.new(2) |> Writer.push("deep", 2)
    assert Writer.to_string(w) == "    deep"
  end

  test "lines are emitted in insertion order" do
    w =
      Writer.new(2)
      |> Writer.push("a", 0)
      |> Writer.push("b", 0)
      |> Writer.push("c", 0)

    assert Writer.to_string(w) == "a\nb\nc"
  end

  test "push_many/3 appends in order" do
    w = Writer.new(2) |> Writer.push_many(["x", "y", "z"], 0)
    assert Writer.to_string(w) == "x\ny\nz"
  end

  test "line_count/1 and empty?/1" do
    w = Writer.new(2)
    assert Writer.empty?(w)
    assert Writer.line_count(w) == 0
    w = Writer.push(w, "line", 0)
    refute Writer.empty?(w)
    assert Writer.line_count(w) == 1
  end

  test "to_iodata/1 produces binary-equivalent output" do
    w = Writer.new(2) |> Writer.push("hello", 0) |> Writer.push("world", 1)
    assert IO.iodata_to_binary(Writer.to_iodata(w)) == Writer.to_string(w)
  end
end
