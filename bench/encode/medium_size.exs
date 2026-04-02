# Medium size encode benchmark
# Tests encoding performance for medium objects (~200 bytes) with nested structures

data_medium = %{
  "user" => %{
    "id" => 123,
    "name" => "Bob",
    "email" => "bob@example.com",
    "active" => true,
    "score" => 98.5
  },
  "tags" => ["elixir", "toon", "llm", "encoding"]
}

Benchee.run(
  %{
    "ToonEx.encode!" => fn -> ToonEx.encode!(data_medium) end,
    "JSON.encode!" => fn -> JSON.encode!(data_medium) end
  },
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true}
  ],
  print: [
    fast_warning: false
  ]
)
