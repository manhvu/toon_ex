alias ToonEx.Decode.{StructuralParser, StructuralParserV2}

opts = %{strict: false, keys: :strings, indent_size: 2}

defmodule Bench do
  def generate_large(n) do
    Enum.map(1..n, fn i ->
      """
      item#{i}:
        name: Item #{i}
        value: #{i * 10}
        tags[3]: tag1,tag2,tag3
      """
    end) |> Enum.join("\n")
  end
end

test_cases = [
  {"simple", """
  name: John
  age: 30
  active: true
  """},
  
  {"nested", """
  user:
    name: John
    address:
      city: NYC
      zip: 10001
    contacts:
      - email: john@example.com
      - phone: 123-456
  """},
  
  {"arrays", """
  items[3]:
    - apple
    - banana
    - cherry
  tags: [3]: web,api,v2
  users[2]{name,age}:
    John,30
    Jane,25
  """},
  
  {"large", Bench.generate_large(100)}
]

IO.puts("\n=== Parser Comparison: V1 (Original) vs V2 (Optimized) ===\n")
IO.puts("Note: V2 parser is experimental and may not handle all edge cases.\n")

Enum.each(test_cases, fn {name, input} ->
  # Warmup
  StructuralParser.parse(input, opts)
  StructuralParserV2.parse(input, opts)
  
  # Benchmark V1
  {v1_time, _} = :timer.tc(fn -> StructuralParser.parse(input, opts) end)
  
  # Benchmark V2
  {v2_time, _} = :timer.tc(fn -> StructuralParserV2.parse(input, opts) end)
  
  speedup = v1_time / v2_time
  IO.puts("#{String.pad_trailing(name, 10)} V1: #{String.pad_leading("#{v1_time} µs", 12)}  V2: #{String.pad_leading("#{v2_time} µs", 12)}  Speedup: #{:erlang.float_to_binary(speedup, [decimals: 2])}x")
end)

IO.puts("\n")
