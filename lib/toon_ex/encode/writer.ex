defmodule ToonEx.Encode.Writer do
  alias ToonEx.Constants

  @type t :: %__MODULE__{lines: [iodata()], indent_string: String.t()}
  defstruct lines: [], indent_string: "  "

  def new(indent_size \\ 2) when is_integer(indent_size) and indent_size > 0 do
    %__MODULE__{lines: [], indent_string: String.duplicate(" ", indent_size)}
  end

  def push(%__MODULE__{} = w, content, depth) when is_integer(depth) and depth >= 0 do
    %{w | lines: [[List.duplicate(w.indent_string, depth), content] | w.lines]}
  end

  def push_many(%__MODULE__{} = w, lines, depth) when is_list(lines) do
    Enum.reduce(lines, w, &push(&2, &1, depth))
  end

  # NEW — returns lines in document order, NO newlines interspersed.
  # Use this when you need to pipe into another Writer or collect for joining.
  @spec to_lines(t()) :: [iodata()]
  def to_lines(%__MODULE__{lines: lines}), do: Enum.reverse(lines)

  # Kept for external callers (e.g. ToonEx.Encode.do_encode → IO.iodata_to_binary).
  # Internally, prefer to_lines/1 + join to avoid the intermediate list from
  # Enum.intersperse.
  @spec to_iodata(t()) :: [iodata()]
  def to_iodata(%__MODULE__{} = w) do
    # Enum.intersperse builds a new list the same length as 2N-1.
    # For large documents prefer: to_lines(w) |> Enum.join("\n")
    w |> to_lines() |> Enum.intersperse(Constants.newline())
  end

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = w), do: w |> to_lines() |> Enum.join("\n")

  def line_count(%__MODULE__{lines: lines}), do: length(lines)
  def empty?(%__MODULE__{lines: []}), do: true
  def empty?(%__MODULE__{}), do: false
end
