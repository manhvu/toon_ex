# Comprehensive Benchmark Suite for ToonEx
# Tests encoding/decoding performance across multiple data sizes and structures
# Compares against standard JSON implementation

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("🚀 ToonEx Comprehensive Benchmark Suite")
IO.puts(String.duplicate("=", 80) <> "\n")

# ============================================================================
# Test Data Generation
# ============================================================================

# Small: Simple flat object (~50 bytes)
data_small = %{"name" => "Alice", "age" => 30}
toon_small = ToonEx.encode!(data_small)
json_small = Jason.encode!(data_small)

# Medium: Nested object with inline array (~200 bytes)
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

toon_medium = ToonEx.encode!(data_medium)
json_medium = Jason.encode!(data_medium)

# Large: Tabular array with 100 rows (~5KB)
data_large_tabular = %{
  "users" =>
    Enum.map(1..100, fn i ->
      %{
        "id" => i,
        "name" => "User#{i}",
        "email" => "user#{i}@example.com",
        "age" => rem(i, 80) + 18,
        "active" => rem(i, 2) == 0,
        "score" => :rand.uniform(1000) / 10.0
      }
    end)
}

toon_large_tabular = ToonEx.encode!(data_large_tabular)
json_large_tabular = Jason.encode!(data_large_tabular)

# Large: Deeply nested structure (~3KB)
data_large_nested = %{
  "organization" => %{
    "name" => "Acme Corp",
    "departments" =>
      Enum.map(1..10, fn d ->
        %{
          "name" => "Dept #{d}",
          "teams" =>
            Enum.map(1..5, fn t ->
              %{
                "name" => "Team #{d}-#{t}",
                "members" =>
                  Enum.map(1..3, fn m ->
                    %{
                      "id" => d * 100 + t * 10 + m,
                      "name" => "Member #{d}-#{t}-#{m}",
                      "role" => if(m == 1, do: "lead", else: "member")
                    }
                  end)
              }
            end)
        }
      end)
  }
}

toon_large_nested = ToonEx.encode!(data_large_nested)
json_large_nested = Jason.encode!(data_large_nested)

# Mixed: Complex structure with all array types (~2KB)
data_mixed = %{
  "metadata" => %{
    "version" => "1.0",
    "tags" => ["production", "v1", "stable"]
  },
  "users" =>
    Enum.map(1..20, fn i ->
      %{
        "id" => i,
        "name" => "User #{i}",
        "roles" => if(rem(i, 2) == 0, do: ["admin", "user"], else: ["user"]),
        "profile" => %{
          "bio" => "Bio for user #{i}",
          "location" => "City #{rem(i, 10)}"
        }
      }
    end),
  "metrics" =>
    Enum.map(1..30, fn i ->
      %{
        "date" => "2024-#{String.pad_leading("#{rem(i, 12) + 1}", 2, "0")}",
        "views" => i * 100,
        "clicks" => i * 10
      }
    end)
}

toon_mixed = ToonEx.encode!(data_mixed)
json_mixed = Jason.encode!(data_mixed)

# ============================================================================
# Benchmark Configuration
# ============================================================================

benchee_opts = [
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true}
  ],
  print: [
    fast_warning: false,
    configuration: false
  ]
]

# ============================================================================
# Run Benchmarks
# ============================================================================

# 1. Encoding Benchmarks
IO.puts("\n📦 ENCODING BENCHMARKS\n" <> String.duplicate("-", 40))

Benchee.run(
  %{
    "ToonEx.encode! (small)" => fn -> ToonEx.encode!(data_small) end,
    "Jason.encode! (small)" => fn -> Jason.encode!(data_small) end
  },
  Keyword.merge(benchee_opts, name: "Encode Small Object")
)

Benchee.run(
  %{
    "ToonEx.encode! (medium)" => fn -> ToonEx.encode!(data_medium) end,
    "Jason.encode! (medium)" => fn -> Jason.encode!(data_medium) end
  },
  Keyword.merge(benchee_opts, name: "Encode Medium Nested Object")
)

Benchee.run(
  %{
    "ToonEx.encode! (large tabular)" => fn -> ToonEx.encode!(data_large_tabular) end,
    "Jason.encode! (large tabular)" => fn -> Jason.encode!(data_large_tabular) end
  },
  Keyword.merge(benchee_opts, name: "Encode Large Tabular Array (100 rows)")
)

Benchee.run(
  %{
    "ToonEx.encode! (large nested)" => fn -> ToonEx.encode!(data_large_nested) end,
    "Jason.encode! (large nested)" => fn -> Jason.encode!(data_large_nested) end
  },
  Keyword.merge(benchee_opts, name: "Encode Large Nested Structure")
)

Benchee.run(
  %{
    "ToonEx.encode! (mixed)" => fn -> ToonEx.encode!(data_mixed) end,
    "Jason.encode! (mixed)" => fn -> Jason.encode!(data_mixed) end
  },
  Keyword.merge(benchee_opts, name: "Encode Mixed Structure")
)

# 2. Decoding Benchmarks
IO.puts("\n📥 DECODING BENCHMARKS\n" <> String.duplicate("-", 40))

Benchee.run(
  %{
    "ToonEx.decode! (small)" => fn -> ToonEx.decode!(toon_small) end,
    "Jason.decode! (small)" => fn -> Jason.decode!(json_small) end
  },
  Keyword.merge(benchee_opts, name: "Decode Small Object")
)

Benchee.run(
  %{
    "ToonEx.decode! (medium)" => fn -> ToonEx.decode!(toon_medium) end,
    "Jason.decode! (medium)" => fn -> Jason.decode!(json_medium) end
  },
  Keyword.merge(benchee_opts, name: "Decode Medium Nested Object")
)

Benchee.run(
  %{
    "ToonEx.decode! (large tabular)" => fn -> ToonEx.decode!(toon_large_tabular) end,
    "Jason.decode! (large tabular)" => fn -> Jason.decode!(json_large_tabular) end
  },
  Keyword.merge(benchee_opts, name: "Decode Large Tabular Array (100 rows)")
)

Benchee.run(
  %{
    "ToonEx.decode! (large nested)" => fn -> ToonEx.decode!(toon_large_nested) end,
    "Jason.decode! (large nested)" => fn -> Jason.decode!(json_large_nested) end
  },
  Keyword.merge(benchee_opts, name: "Decode Large Nested Structure")
)

Benchee.run(
  %{
    "ToonEx.decode! (mixed)" => fn -> ToonEx.decode!(toon_mixed) end,
    "Jason.decode! (mixed)" => fn -> Jason.decode!(json_mixed) end
  },
  Keyword.merge(benchee_opts, name: "Decode Mixed Structure")
)

# 3. Size/Token Efficiency Comparison
IO.puts("\n📏 SIZE EFFICIENCY COMPARISON\n" <> String.duplicate("-", 40))

size_tests = [
  {"Small Object", data_small},
  {"Medium Nested Object", data_medium},
  {"Large Tabular Array (100 rows)", data_large_tabular},
  {"Large Nested Structure", data_large_nested},
  {"Mixed Structure", data_mixed}
]

Enum.each(size_tests, fn {name, data} ->
  toon = ToonEx.encode!(data)
  json = Jason.encode!(data)

  toon_size = byte_size(toon)
  json_size = byte_size(json)
  reduction = Float.round((1 - toon_size / json_size) * 100, 1)

  IO.puts("#{name}:")
  IO.puts("  TOON: #{toon_size} bytes")
  IO.puts("  JSON: #{json_size} bytes")
  IO.puts("  Reduction: #{reduction}%")
  IO.puts("")
end)

IO.puts(String.duplicate("=", 80))
IO.puts("✅ Benchmark suite complete!\n")
