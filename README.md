# ToonEx

[![Hex.pm](https://img.shields.io/hexpm/v/toon_ex.svg)](https://hex.pm/packages/toon_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/toon_ex)
[![License: MIT](https://img.shields.io/badge/license-MIT-fef3c0?labelColor=1b1b1f)](./LICENSE.md)

**TOON (Token-Oriented Object Notation)** high performance encoder and decoder for Elixir and Phoenix Channels.

TOON is a compact data format optimized for LLM token efficiency.

The library is supported for Phoenix Channels. Guide in `ToonEx.Phoenix.Serializer` module.

*Completed with support from AI.*

## Features

- 🎯 **Token Efficient**: 30-60% fewer tokens than JSON
- 📖 **Human Readable**: Indentation-based structure like YAML
- ✅ **Spec Compliant**: Tested against official TOON v1.3 specification
- 🔌 **Protocol Support**: Custom encoding via `ToonEx.Encoder` protocol
- 🛠️ **Convertor**: Support convert between JSON & TOON
- 💻 **Phoenix Channels**: Support for serializer/parser

## Installation

Add `toon_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:toon_ex, "~> 0.3.4"}
  ]
end
```

## Quick Start

### Encoding

```elixir
# Simple object
ToonEx.encode!(%{"name" => "Alice", "age" => 30})
# => "age: 30\\nname: Alice"

# Nested object
ToonEx.encode!(%{"user" => %{"name" => "Bob"}})
# => "user:\\n  name: Bob"

# Arrays
ToonEx.encode!(%{"tags" => ["elixir", "toon"]})
# => "tags[2]: elixir,toon"
```

### Decoding

```elixir
ToonEx.decode!("name: Alice\\nage: 30")
# => %{"name" => "Alice", "age" => 30}

ToonEx.decode!("tags[2]: a,b")
# => %{"tags" => ["a", "b"]}

# With options
ToonEx.decode!("user:\\n    name: Alice", indent_size: 4)
# => %{"user" => %{"name" => "Alice"}}
```

## Comprehensive Examples

### Primitives

```elixir
ToonEx.encode!(nil)            # => "null"
ToonEx.encode!(true)           # => "true"
ToonEx.encode!(42)             # => "42"
ToonEx.encode!(3.14)           # => "3.14"
ToonEx.encode!("hello")        # => "hello"
ToonEx.encode!("hello world")  # => "\\"hello world\\"" (auto-quoted)
```

### Objects

```elixir
# Simple objects
ToonEx.encode!(%{"name" => "Alice", "age" => 30})
# =>
# age: 30
# name: Alice

# Nested objects
ToonEx.encode!(%{
  "user" => %{
    "name" => "Bob",
    "email" => "bob@example.com"
  }
})
# =>
# user:
#   email: bob@example.com
#   name: Bob
```

### Arrays

```elixir
# Inline arrays (primitives)
ToonEx.encode!(%{"tags" => ["elixir", "toon", "llm"]})
# => "tags[3]: elixir,toon,llm"

# Tabular arrays (uniform objects)
ToonEx.encode!(%{
  "users" => [
    %{"name" => "Alice", "age" => 30},
    %{"name" => "Bob", "age" => 25}
  ]
})
# => "users[2]{age,name}:\\n  30,Alice\\n  25,Bob"

# List-style arrays (mixed or nested)
ToonEx.encode!(%{
  "items" => [
    %{"type" => "book", "title" => "Elixir Guide"},
    %{"type" => "video", "duration" => 120}
  ]
})
# => "items[2]:\\n  - duration: 120\\n    type: video\\n  - title: \\"Elixir Guide\\"\\n    type: book"
```

### Encoding Options

```elixir
# Custom delimiters
ToonEx.encode!(%{"tags" => ["a", "b", "c"]}, delimiter: "\\t")
# => "tags[3\\t]: a\\tb\\tc"

ToonEx.encode!(%{"values" => [1, 2, 3]}, delimiter: "|")
# => "values[3|]: 1|2|3"

# Length markers
ToonEx.encode!(%{"tags" => ["a", "b", "c"]}, length_marker: "#")
# => "tags[#3]: a,b,c"

# Custom indentation
ToonEx.encode!(%{"user" => %{"name" => "Alice"}}, indent: 4)
# => "user:\\n    name: Alice"
```

### Decoding Options

```elixir
# Atom keys
ToonEx.decode!("name: Alice", keys: :atoms)
# => %{name: "Alice"}

# Custom indent size
ToonEx.decode!("user:\\n    name: Alice", indent_size: 4)
# => %{"user" => %{"name" => "Alice"}}

# Strict mode (default: true)
ToonEx.decode!("  name: Alice", strict: false)  # Accepts non-standard indentation
# => %{"name" => "Alice"}
```

## Specification Compliance

This implementation is tested against the [official TOON specification v1.3](https://github.com/toon-format/spec).

## Limitation

Not support for validated TOON in current version.

Not optimized for high traffic application yet.

## Testing

The test suite uses official TOON specification fixtures:

```bash
# Run all tests against official spec fixtures
mix test

# Run only fixture-based tests
mix test test/toon_ex/fixtures_test.exs
```

Test fixtures are loaded from the [toon-format/spec](https://github.com/toon-format/spec) repository via git submodule.

## TOON Specification

This implementation follows [TOON Specification v1.3](https://github.com/toon-format/spec/blob/main/SPEC.md).

## Contributing

Contributions are welcome!

## Author

Created by
**Kentaro Kuribayashi**

Maintained and optimized by
**Manh Vu**

## License

MIT License - see [LICENSE](LICENSE).
