data_small = %{"name" => "Alice", "age" => 30}

Benchee.run(
  %{
    "ToonEx.encode! (small)" => fn -> ToonEx.encode!(data_small) end,
    "JSON.encode! (small)" => fn -> JSON.encode!(data_small) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
