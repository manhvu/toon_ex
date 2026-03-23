defmodule ToonEx.Fixtures.UserWithExcept do
  @moduledoc false
  @derive {ToonEx.Encoder, except: [:password]}
  defstruct [:name, :email, :password]
end

defmodule ToonEx.Fixtures.CustomDate do
  @moduledoc "Test struct with explicit ToonEx.Encoder implementation"
  defstruct [:year, :month, :day]
end

defimpl ToonEx.Encoder, for: ToonEx.Fixtures.CustomDate do
  def encode(%{year: y, month: m, day: d}, _opts) do
    "#{y}-#{String.pad_leading(to_string(m), 2, "0")}-#{String.pad_leading(to_string(d), 2, "0")}"
  end
end

defmodule ToonEx.Fixtures.Person do
  @moduledoc false
  @derive ToonEx.Encoder
  defstruct [:name, :age]
end

defmodule ToonEx.Fixtures.Company do
  @moduledoc false
  @derive ToonEx.Encoder
  defstruct [:name, :ceo]
end

defmodule ToonEx.Fixtures.UserWithOnly do
  @moduledoc false
  @derive {ToonEx.Encoder, only: [:name]}
  defstruct [:name, :email, :password]
end

defmodule ToonEx.Fixtures.StructWithoutEncoder do
  @moduledoc "Test struct without ToonEx.Encoder implementation"
  defstruct [:id, :value]
end
