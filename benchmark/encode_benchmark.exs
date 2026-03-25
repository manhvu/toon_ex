data_small = %{"name" => "Alice", "age" => 30}

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

data_large = %{
  "users" =>
    Enum.map(1..50, fn i ->
      %{
        "id" => i,
        "name" => "User#{i}",
        "email" => "user#{i}@example.com",
        "age" => rem(i, 80) + 18,
        "active" => rem(i, 2) == 0
      }
    end),
  "metadata" => %{
    "total" => 50,
    "page" => 1,
    "per_page" => 50
  }
}

Benchee.run(
  %{
    "ToonEx.encode! (small)" => fn -> ToonEx.encode!(data_small) end,
    "Jason.encode! (small)" => fn -> JSON.encode!(data_small) end,
    "ToonEx.encode! (medium)" => fn -> ToonEx.encode!(data_medium) end,
    "Jason.encode! (medium)" => fn -> JSON.encode!(data_medium) end,
    "ToonEx.encode! (large)" => fn -> ToonEx.encode!(data_large) end,
    "Jason.encode! (large)" => fn -> JSON.encode!(data_large) end
  },
  time: 5,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
