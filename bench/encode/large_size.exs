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
    "ToonEx.encode! (large)" => fn -> ToonEx.encode!(data_large) end,
    "JSON.encode! (large)" => fn -> JSON.encode!(data_large) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
