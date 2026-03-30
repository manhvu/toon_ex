defmodule ToonEx.Decode.ComplexObjectTest do
  use ExUnit.Case, async: true

  # ── inline arrays (key[N]: v1,v2) ───────────────────────────────────────────

  describe "Phoenix Array" do
    test "Complex array 1" do
      string = """
      [5]:
        - "1"
        - "2"
        - channel:room1
        - user_location
        - user_id: ""
          packet_id: 988586b4-d0b8-4703-94d3-725d9dffdd60
          token: ""
          device_id: test
          gps_data:
            timestamp: 30522
            lon: -122.03852007
            lat: 37.3325448
            ele: 0
      """

      expected =
        [
          "1",
          "2",
          "channel:room1",
          "user_location",
          %{
            "user_id" => "",
            "packet_id" => "988586b4-d0b8-4703-94d3-725d9dffdd60",
            "token" => "",
            "device_id" => "test",
            "gps_data" => %{
              "timestamp" => 30522,
              "lon" => -122.03852007,
              "lat" => 37.3325448,
              "ele" => 0
            }
          }
        ]

      result = ToonEx.decode!(string)

      assert expected == result
    end

    test "comlex object 1" do
      string = """
      user_id: ""
      packet_id: 988586b4-d0b8-4703-94d3-725d9dffdd60
      token: ""
      device_id: test
      gps_data:
        empty_field:
        timestamp: 30522
        lon: -122.03852007
        lat: 37.3325448
        ele: 0

      """

      expected =
        %{
          "user_id" => "",
          "packet_id" => "988586b4-d0b8-4703-94d3-725d9dffdd60",
          "token" => "",
          "device_id" => "test",
          "gps_data" => %{
            "empty_field" => %{},
            "timestamp" => 30522,
            "lon" => -122.03852007,
            "lat" => 37.3325448,
            "ele" => 0
          }
        }

      result = ToonEx.decode!(string)

      assert expected == result
    end

    test "common object 1" do
      # ↓ indent 6 (was 4) — one extra level inside args:
      toon =
        "[5]:\n" <>
          "  - \"1\"\n" <>
          "  - \"4\"\n" <>
          "  - \"gen_api:019d372d-07f7-7403-852e-018c86f36cb3\"\n" <>
          "  - gen_api\n" <>
          "  - args: \n" <>
          "      device_id: 4bfc7b44-704a-4cbb-a7c3-fdc82352c580\n" <>
          "      request_id: 19e35116-b76b-470b-afc0-d5b9e2ccb69f\n" <>
          "      request_type: get_data\n" <>
          "      service: db"

      assert match?(
               [
                 "1",
                 "4",
                 "gen_api:019d372d-07f7-7403-852e-018c86f36cb3",
                 "gen_api",
                 %{
                   args: %{
                     device_id: "4bfc7b44-704a-4cbb-a7c3-fdc82352c580",
                     request_id: "19e35116-b76b-470b-afc0-d5b9e2ccb69f",
                     request_type: "get_data",
                     service: "db"
                   }
                 }
               ],
               ToonEx.decode!(toon, keys: :atoms)
             )
    end
  end
end
