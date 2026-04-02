# Medium size decode benchmark
# Tests decoding performance for medium objects (~200 bytes) with nested structures

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
    "ToonEx.decode!" => fn -> ToonEx.decode!(toon_medium) end,
    "JSON.decode!" => fn -> JSON.decode!(json_medium) end
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
