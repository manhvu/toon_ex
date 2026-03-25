# Dialyzer warnings to ignore
#
# Protocol fallback implementation that intentionally raises.
# This is expected behavior - the Any implementation raises Protocol.UndefinedError
# when a struct doesn't have an explicit ToonEx.Encoder implementation.
[
  {"lib/toon_ex/encoder.ex", :no_return}
]
