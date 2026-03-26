toon_medium = """
id: 123
name: Bob
email: bob@example.com
active: true
score: 98.5
tags[4]: elixir,toon,llm,encoding
"""

json_medium =
  JSON.encode!(%{
    "id" => 123,
    "name" => "Bob",
    "email" => "bob@example.com",
    "active" => true,
    "score" => 98.5,
    "tags" => ["elixir", "toon", "llm", "encoding"]
  })

Benchee.run(
  %{
    "ToonEx.decode! (medium)" => fn -> ToonEx.decode!(toon_medium) end,
    "JSON.decode! (medium)" => fn -> JSON.decode!(json_medium) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
