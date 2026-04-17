defmodule ToonEx.Encode.Writer do
  alias ToonEx.Constants

  @type t :: %__MODULE__{lines: [iodata()], indent_string: String.t()}
  defstruct lines: [], indent_string: "  "

  def new(indent_size \\ 2) when is_integer(indent_size) and indent_size > 0 do
    %__MODULE__{lines: [], indent_string: String.duplicate(" ", indent_size)}
  end

  # Performance: Use :binary.copy for repeated string duplication - faster than String.duplicate
  @compile {:inline, build_indent: 2}
  defp build_indent(indent_string, depth) when depth >= 0 do
    :binary.copy(indent_string, depth)
  end

  def push(%__MODULE__{} = w, content, depth) when is_integer(depth) and depth >= 0 do
    indent = build_indent(w.indent_string, depth)
    %{w | lines: [[indent, content] | w.lines]}
  end

  def push_many(%__MODULE__{} = w, lines, depth) when is_list(lines) do
    indent = build_indent(w.indent_string, depth)
    # Performance: Single-pass accumulation instead of repeated push calls
    new_lines = Enum.reduce(lines, w.lines, fn line, acc -> [[indent, line] | acc] end)
    %{w | lines: new_lines}
  end

  # Performance: Use :lists.reverse instead of Enum.reverse for better performance
  @spec to_lines(t()) :: [iodata()]
  def to_lines(%__MODULE__{lines: lines}), do: :lists.reverse(lines)

  # Performance: Build iodata tree directly without Enum.intersperse intermediate list
  @spec to_iodata(t()) :: iodata()
  def to_iodata(%__MODULE__{} = w) do
    lines = :lists.reverse(w.lines)
    newline = Constants.newline()
    # Build iodata tree: [line1, "\n", line2, "\n", ...]
    do_build_iodata(lines, newline, [])
  end

  # Tail-recursive iodata builder - avoids Enum.intersperse allocation
  defp do_build_iodata([], _newline, acc), do: :lists.reverse(acc)
  defp do_build_iodata([line], _newline, acc), do: :lists.reverse([line | acc])

  defp do_build_iodata([line | rest], newline, acc),
    do: do_build_iodata(rest, newline, [newline, line | acc])

  @spec to_string(t()) :: String.t()
  # Performance: Use to_iodata/1 which already builds the iolist tree with
  # newlines interspersed, then convert to binary once at the boundary.
  # This avoids Enum.join("\n") which creates intermediate binary strings.
  def to_string(%__MODULE__{} = w), do: IO.iodata_to_binary(to_iodata(w))

  def line_count(%__MODULE__{lines: lines}), do: length(lines)
  def empty?(%__MODULE__{lines: []}), do: true
  def empty?(%__MODULE__{}), do: false
end
