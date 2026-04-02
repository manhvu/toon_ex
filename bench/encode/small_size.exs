# Small size encode benchmark
# Tests encoding performance for small objects (~50 bytes)

data_small = %{"name" => "Alice", "age" => 30}

Benchee.run(
  %{
    "ToonEx.encode!" => fn -> ToonEx.encode!(data_small) end,
    "JSON.encode!" => fn -> JSON.encode!(data_small) end
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
