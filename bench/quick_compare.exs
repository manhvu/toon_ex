# Quick performance comparison benchmark
# Run with: mix run bench/quick_compare.exs

defmodule BenchData do
  def small_object, do: %{"name" => "Alice", "age" => 30, "active" => true}

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
        %{"name" => "ToonEx", "description" => "High-performance TOON encoder/decoder", "stars" => 1250, "language" => "Elixir", "tags" => ["encoding", "decoding", "performance"]},
        %{"name" => "PhoenixApp", "description" => "Real-time web application", "stars" => 890, "language" => "Elixir", "tags" => ["web", "real-time", "channels"]},
        %{"name" => "DataPipeline", "description" => "ETL pipeline for analytics", "stars" => 456, "language" => "Python", "tags" => ["data", "etl", "analytics"]}
      ],
      "metrics" => %{"requests" => 1_234_567, "errors" => 42, "latency_p99" => 125.5, "uptime" => 99.99}
    }
  end

  def tabular_array_100 do
    Enum.map(1..100, fn i ->
      %{"id" => i, "name" => "User_#{i}", "email" => "user#{i}@example.com", "score" => :rand.uniform(100), "active" => rem(i, 2) == 0}
    end)
  end

  def tabular_array_500 do
    Enum.map(1..500, fn i ->
      %{"id" => i, "name" => "User_#{i}", "email" => "user#{i}@example.com", "score" => :rand.uniform(100), "active" => rem(i, 2) == 0}
    end)
  end

  def string_with_escapes do
    %{"message" => "Hello \"World\"\nNew line\tTabbed\\Backslash", "path" => "C:\\Users\\test\\file.txt"}
  end
end

inputs = %{
  "encode_small" => BenchData.small_object(),
  "encode_medium" => BenchData.medium_object(),
  "encode_large" => BenchData.large_object(),
  "encode_escapes" => BenchData.string_with_escapes(),
  "encode_tabular_100" => BenchData.tabular_array_100(),
  "encode_tabular_500" => BenchData.tabular_array_500(),
  "decode_small" => ToonEx.encode!(BenchData.small_object()),
  "decode_medium" => ToonEx.encode!(BenchData.medium_object()),
  "decode_large" => ToonEx.encode!(BenchData.large_object()),
  "decode_escapes" => ToonEx.encode!(BenchData.string_with_escapes()),
  "decode_tabular_100" => ToonEx.encode!(BenchData.tabular_array_100()),
  "decode_tabular_500" => ToonEx.encode!(BenchData.tabular_array_500()),
}

Benchee.run(
  %{
    "encode" => fn input -> ToonEx.encode!(input) end,
    "decode" => fn input -> ToonEx.decode!(input) end
  },
  inputs: inputs,
  time: 3,
  memory_time: 1,
  formatters: [{Benchee.Formatters.Console, comparisons: true}]
)
