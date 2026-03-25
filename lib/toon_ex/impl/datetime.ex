defimpl ToonEx.Encoder, for: DateTime do
  def encode(%DateTime{} = struct, _opts) do
    DateTime.to_string(struct)
  end
end

defimpl ToonEx.Encoder, for: Date do
  def encode(%Date{} = struct, _opts) do
    Date.to_string(struct)
  end
end
