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
    "ToonEx.encode! (medium)" => fn -> ToonEx.encode!(data_medium) end,
    "JSON.encode! (medium)" => fn -> JSON.encode!(data_medium) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
