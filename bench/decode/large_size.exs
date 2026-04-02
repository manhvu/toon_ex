# Large size decode benchmark
# Tests decoding performance for large objects (~5KB) with tabular arrays

data_large = %{
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

toon_large = ToonEx.encode!(data_large)
json_large = JSON.encode!(data_large)

Benchee.run(
  %{
    "ToonEx.decode!" => fn -> ToonEx.decode!(toon_large) end,
    "JSON.decode!" => fn -> JSON.decode!(json_large) end
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
