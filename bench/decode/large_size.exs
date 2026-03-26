data = %{
  "users" =>
    Enum.map(1..100, fn i ->
      %{
        "id" => i,
        "name" => "User#{i}",
        "email" => "user#{i}@example.com",
        "age" => rem(i, 80) + 18,
        "active" => rem(i, 2) == 0
      }
    end),
  "metadatas" =>
    Enum.map(1..100, fn i ->
      %{
        "page" => i,
        "per_page" => 50
      }
    end)
}

toon_large = ToonEx.encode!(data)

json_large =
  JSON.encode!(data)

Benchee.run(
  %{
    "ToonEx.decode! (large)" => fn -> ToonEx.decode!(toon_large) end,
    "JSON.decode! (large)" => fn -> JSON.decode!(json_large) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
