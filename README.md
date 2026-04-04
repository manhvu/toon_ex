# ToonEx

[![Hex.pm](https://img.shields.io/hexpm/v/toon_ex.svg)](https://hex.pm/packages/toon_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/toon_ex)
[![License: MIT](https://img.shields.io/badge/license-MIT-fef3c0?labelColor=1b1b1f)](./LICENSE)

High-performance TOON (Token-Oriented Object Notation) encoder/decoder for Elixir with Phoenix Channels support.

TOON is a compact, human-readable data format optimized for LLM token efficiency.

## Features

- 🎯 **Token Efficient**: 30-60% fewer tokens than JSON
- 📖 **Human Readable**: Indentation-based structure like YAML
- ✅ **Spec Compliant**: Tested against official TOON v1.3 specification (306 tests)
- 🔌 **Phoenix Channels**: Built-in serializer support
- 🛠️ **JSON Converter**: Bidirectional JSON ↔ TOON conversion
- 🔧 **Extensible**: Custom encoding via `ToonEx.Encoder` protocol

## Installation

Add `toon_ex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:toon_ex, "~> 0.5"}
  ]
end
```

## Quick Start

### Encoding

```elixir
# Simple object
ToonEx.encode!(%{"name" => "Alice", "age" => 30})
# => "age: 30\nname: Alice"

# Nested object
ToonEx.encode!(%{"user" => %{"name" => "Bob"}})
# => "user:\n  name: Bob"

# Arrays
ToonEx.encode!(%{"tags" => ["elixir", "toon"]})
# => "tags[2]: elixir,toon"
```

### Decoding

```elixir
ToonEx.decode!("name: Alice\nage: 30")
# => %{"name" => "Alice", "age" => 30}

ToonEx.decode!("tags[2]: a,b")
# => %{"tags" => ["a", "b"]}

# Atom keys
ToonEx.decode!("name: Alice", keys: :atoms)
# => %{name: "Alice"}
```

### Phoenix Channels

```elixir
# In your endpoint configuration
config :my_app, MyApp.Endpoint,
  websocket: [
    serializer: [{ToonEx.Phoenix.Serializer, "~> 1.0"}]
  ]
```

See `ToonEx.Phoenix.Serializer` for details.

## API Reference

### Core Functions

- `ToonEx.encode/2` - Encode data to TOON string (returns `{:ok, string} | {:error, error}`)
- `ToonEx.encode!/2` - Encode data to TOON string (raises on error)
- `ToonEx.decode/2` - Decode TOON string to data (returns `{:ok, data} | {:error, error}`)
- `ToonEx.decode!/2` - Decode TOON string to data (raises on error)

### Encoding Options

- `:indent` - Spaces for indentation (default: `2`)
- `:delimiter` - Array value delimiter: `","` | `"\t"` | `"|"` (default: `","`)
- `:length_marker` - Length marker prefix (default: `nil`)

### Decoding Options

- `:keys` - Map key type: `:strings` | `:atoms` | `:atoms!` (default: `:strings`)
- `:indent_size` - Expected indentation size (default: `2`)
- `:strict` - Strict mode validation (default: `true`)

## Modules

- **ToonEx** - Main API
- **ToonEx.Encode** - Encoder implementation
- **ToonEx.Decode** - Decoder implementation
- **ToonEx.JSON** - JSON ↔ TOON converter
- **ToonEx.Encoder** - Protocol for custom struct encoding
- **ToonEx.Phoenix.Serializer** - Phoenix Channels serializer

## Specification

This implementation follows [TOON Specification v1.3](https://github.com/toon-format/spec/blob/main/SPEC.md) and is tested against official fixtures.

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Code quality checks
mix quality
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT License - see [LICENSE](LICENSE).