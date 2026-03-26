toon_small = "name: Alice\nage: 30"
json_small = JSON.encode!(%{"name" => "Alice", "age" => 30})

Benchee.run(
  %{
    "ToonEx.decode! (medium)" => fn -> ToonEx.decode!(toon_small) end,
    "JSON.decode! (medium)" => fn -> JSON.decode!(json_small) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
