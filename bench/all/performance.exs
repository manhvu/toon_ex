# Comprehensive Performance Benchmark for ToonEx
#
# Tests encoding and decoding performance across different data sizes
# and complexity levels. Compares TOON vs JSON where applicable.
#
# Run with: mix run bench/all/performance.exs

alias ToonEx.Encode.Arrays

# ============================================================================
# Test Data Generation
# ============================================================================

defmodule BenchData do
  @moduledoc false

  def small_object do
    %{"name" => "Alice", "age" => 30, "active" => true}
  end

  def medium_object do
    %{
      "id" => 12_345,
      "name" => "Bob Smith",
      "email" => "bob@example.com",
      "active" => true,
      "score" => 98.5,
      "tags" => ["elixir", "toon", "llm", "encoding"],
      "address" => %{
        "street" => "123 Main St",
        "city" => "Portland",
        "state" => "OR",
        "zip" => "97201"
      }
    }
  end

  def large_object do
    %{
      "user" => %{
        "id" => 98_765,
        "name" => "Charlie Brown",
        "email" => "charlie@example.com",
        "created_at" => "2024-01-15T10:30:00Z",
        "profile" => %{
          "bio" => "Software engineer passionate about Elixir and functional programming",
          "avatar_url" => "https://example.com/avatars/charlie.jpg",
          "website" => "https://charlie.dev",
          "location" => "San Francisco, CA"
        },
        "settings" => %{
          "theme" => "dark",
          "notifications" => true,
          "language" => "en",
          "timezone" => "America/Los_Angeles"
        }
      },
      "projects" => [
        %{
          "name" => "ToonEx",
          "description" => "High-performance TOON encoder/decoder",
          "stars" => 1250,
          "language" => "Elixir",
          "tags" => ["encoding", "decoding", "performance"]
        },
        %{
          "name" => "PhoenixApp",
          "description" => "Real-time web application",
          "stars" => 890,
          "language" => "Elixir",
          "tags" => ["web", "real-time", "channels"]
        },
        %{
          "name" => "DataPipeline",
          "description" => "ETL pipeline for analytics",
          "stars" => 456,
          "language" => "Python",
          "tags" => ["data", "etl", "analytics"]
        }
      ],
      "metrics" => %{
        "requests" => 1_234_567,
        "errors" => 42,
        "latency_p99" => 125.5,
        "uptime" => 99.99
      }
    }
  end

  def primitive_array_100 do
    Enum.map(1..100, &"item_#{&1}")
  end

  def primitive_array_1000 do
    Enum.map(1..1000, &"item_#{&1}")
  end

  def tabular_array_50 do
    Enum.map(1..50, fn i ->
      %{
        "id" => i,
        "name" => "User_#{i}",
        "email" => "user#{i}@example.com",
        "score" => :rand.uniform(100),
        "active" => rem(i, 2) == 0
      }
    end)
  end

  def tabular_array_500 do
    Enum.map(1..500, fn i ->
      %{
        "id" => i,
        "name" => "User_#{i}",
        "email" => "user#{i}@example.com",
        "score" => :rand.uniform(100),
        "active" => rem(i, 2) == 0
      }
    end)
  end

  def list_array_20 do
    Enum.map(1..20, fn i ->
      if rem(i, 3) == 0 do
        %{
          "type" => "complex",
          "data" => %{
            "nested" => %{
              "value" => i,
              "items" => ["a", "b", "c"]
            }
          }
        }
      else
        %{
          "type" => "simple",
          "value" => i,
          "tags" => ["tag_#{i}"]
        }
      end
    end)
  end

  def deeply_nested do
    %{
      "level1" => %{
        "level2" => %{
          "level3" => %{
            "level4" => %{
              "level5" => %{
                "value" => "deep",
                "numbers" => [1, 2, 3, 4, 5],
                "metadata" => %{
                  "created" => "2024-01-01",
                  "version" => 2
                }
              }
            }
          }
        }
      }
    }
  end

  def string_with_escapes do
    %{
      "message" => "Hello \"World\"\nNew line\tTabbed\\Backslash",
      "path" => "C:\\Users\\test\\file.txt",
      "json_like" => "{\"key\": \"value\", \"nested\": {\"a\": 1}}"
    }
  end

  def toon_string(data) do
    ToonEx.encode!(data)
  end

  def json_string(data) do
    JSON.encode!(data)
  end
end

# ============================================================================
# Benchmark Configuration
# ============================================================================

inputs = %{
  # Object encoding
  "encode_small_object" => BenchData.small_object(),
  "encode_medium_object" => BenchData.medium_object(),
  "encode_large_object" => BenchData.large_object(),
  "encode_deeply_nested" => BenchData.deeply_nested(),
  "encode_string_escapes" => BenchData.string_with_escapes(),

  # Array encoding
  "encode_primitive_array_100" => BenchData.primitive_array_100(),
  "encode_primitive_array_1000" => BenchData.primitive_array_1000(),
  "encode_tabular_array_50" => BenchData.tabular_array_50(),
  "encode_tabular_array_500" => BenchData.tabular_array_500(),
  "encode_list_array_20" => BenchData.list_array_20(),

  # Object decoding
  "decode_small_object" => BenchData.toon_string(BenchData.small_object()),
  "decode_medium_object" => BenchData.toon_string(BenchData.medium_object()),
  "decode_large_object" => BenchData.toon_string(BenchData.large_object()),
  "decode_deeply_nested" => BenchData.toon_string(BenchData.deeply_nested()),
  "decode_string_escapes" => BenchData.toon_string(BenchData.string_with_escapes()),

  # Array decoding
  "decode_primitive_array_100" => BenchData.toon_string(BenchData.primitive_array_100()),
  "decode_primitive_array_1000" => BenchData.toon_string(BenchData.primitive_array_1000()),
  "decode_tabular_array_50" => BenchData.toon_string(BenchData.tabular_array_50()),
  "decode_tabular_array_500" => BenchData.toon_string(BenchData.tabular_array_500()),
  "decode_list_array_20" => BenchData.toon_string(BenchData.list_array_20()),

  # Round-trip
  "roundtrip_small_object" => BenchData.small_object(),
  "roundtrip_medium_object" => BenchData.medium_object(),
  "roundtrip_large_object" => BenchData.large_object(),
  "roundtrip_primitive_array_100" => BenchData.primitive_array_100(),
  "roundtrip_tabular_array_50" => BenchData.tabular_array_50()
}

# ============================================================================
# Run Benchmarks
# ============================================================================

Benchee.run(
  %{
    "ToonEx.encode!" => fn input -> ToonEx.encode!(input) end,
    "ToonEx.decode!" => fn input -> ToonEx.decode!(input) end,
    "ToonEx roundtrip" => fn input ->
      input
      |> ToonEx.encode!()
      |> ToonEx.decode!()
    end
  },
  inputs: inputs,
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true, extended_statistics: true, column_width: 80}
  ],
  print: [
    fast_warning: false,
    configuration: true
  ],
  save: [path: "bench/all/results.benchee", tag: "baseline"]
)

# ============================================================================
# Size Comparison Report
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TOON vs JSON Size Comparison")
IO.puts(String.duplicate("=", 80))

size_tests = [
  {"Small Object", BenchData.small_object()},
  {"Medium Object", BenchData.medium_object()},
  {"Large Object", BenchData.large_object()},
  {"Deeply Nested", BenchData.deeply_nested()},
  {"Primitive Array (100)", BenchData.primitive_array_100()},
  {"Tabular Array (50)", BenchData.tabular_array_50()},
  {"List Array (20)", BenchData.list_array_20()}
]

Enum.each(size_tests, fn {name, data} ->
  toon_size = byte_size(ToonEx.encode!(data))
  json_size = byte_size(JSON.encode!(data))
  savings = ((1 - toon_size / json_size) * 100) |> Float.round(1)

  IO.puts("\n#{name}:")
  IO.puts("  TOON: #{toon_size} bytes")
  IO.puts("  JSON: #{json_size} bytes")
  IO.puts("  Savings: #{savings}%")
end)
