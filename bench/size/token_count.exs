# Token count comparison between TOON and JSON
# This measures the actual string size as a proxy for token count

data_sets = [
  {"Small object", %{"name" => "Alice", "age" => 30}},
  {"Medium object",
   %{
     "user" => %{"name" => "Bob", "email" => "bob@example.com"},
     "tags" => ["elixir", "toon", "llm"]
   }},
  {"Array of objects",
   %{
     "users" =>
       Enum.map(1..100, fn i ->
         %{"name" => "User#{i}", "age" => 20 + i, "meta: #{i}" => i}
       end)
   }},
  {"Array of objects - Tabular",
   %{
     "users" =>
       Enum.map(1..100, fn i ->
         %{"name" => "User#{i}", "age" => 20 + i}
       end)
   }},
  {"Nested object",
   %{
     "user" => %{"name" => "Bob", "email" => "bob@example.com"},
     "meta" => %{
       "login" => %{
         "count" => 1000,
         "session" => %{"last" => %{"ip" => "192.168.0.2"}, "old" => %{"ip" => "192.168.0.32"}}
       }
     }
   }}
]

IO.puts("\n=== Token Efficiency Comparison ===\n")

Enum.each(data_sets, fn {name, data} ->
  toon = ToonEx.encode!(data)
  json = Jason.encode!(data)

  toon_size = byte_size(toon)
  json_size = byte_size(json)
  reduction = Float.round((1 - toon_size / json_size) * 100, 1)

  IO.puts("#{name}:")
  IO.puts("  TOON: #{toon_size} bytes")
  IO.puts("  JSON: #{json_size} bytes")
  IO.puts("  Reduction: #{reduction}%")
  IO.puts("")
end)
