# Small size decode benchmark
# Tests decoding performance for small objects (~50 bytes)

toon_small = "name: Alice\nage: 30"
json_small = JSON.encode!(%{"name" => "Alice", "age" => 30})

Benchee.run(
  %{
    "ToonEx.decode!" => fn -> ToonEx.decode!(toon_small) end,
    "JSON.decode!" => fn -> JSON.decode!(json_small) end
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
