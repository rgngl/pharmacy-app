defmodule PharmacyApp.Pharmacies.PlacesAdapterRequestTest do
  use ExUnit.Case, async: false

  alias PharmacyApp.Pharmacies.PlacesAdapter

  @geocode_mask "places.id,places.formattedAddress,places.location"

  @nearby_mask "places.id,places.displayName,places.formattedAddress,places.location," <>
                 "places.currentOpeningHours,places.nationalPhoneNumber,places.utcOffsetMinutes," <>
                 "routingSummaries"

  @wire_place %{
    "id" => "p1",
    "displayName" => %{"text" => "Apotheke Mitte"},
    "formattedAddress" => "Friedrichstraße 1, 10117 Berlin",
    "location" => %{"latitude" => 52.5215, "longitude" => 13.405}
  }

  setup do
    on_exit(fn ->
      :telemetry.detach("places-request-test")
      Application.delete_env(:pharmacy_app, :places_req_opts)
      Application.delete_env(:pharmacy_app, :places_receive_timeout)
    end)

    attach_telemetry()
    Process.put(:places_fake_reply, {:ok, %{"places" => []}})
    :ok
  end

  defp attach_telemetry do
    parent = self()

    :telemetry.attach_many(
      "places-request-test",
      [
        [:pharmacy_app, :places, :request, :start],
        [:pharmacy_app, :places, :request, :stop],
        [:pharmacy_app, :places, :request, :exception]
      ],
      fn event, measurements, meta, _ -> send(parent, {:telemetry, event, measurements, meta}) end,
      nil
    )
  end

  # Installs the fake adapter and runs `fun` with the adapter scripted to
  # answer with `replay`.
  defp with_adapter(replay, fun) do
    Process.put(:places_fake_reply, replay)
    Application.put_env(:pharmacy_app, :places_req_opts, adapter: PlacesFakeAdapter, retry: false)
    fun.()
  end

  defp captured_request, do: Process.get(:places_fake_req)

  defp decode_body do
    Jason.decode!(IO.iodata_to_binary(captured_request().body))
  end

  # -- geocode/2 -------------------------------------------------------------

  describe "geocode/2" do
    test "happy path: resolves the top hit and asserts the wire request" do
      result =
        with_adapter(
          {:ok,
           %{
             "places" => [
               @wire_place
               |> Map.put("formattedAddress", "Alexanderstraße 1, 10178 Berlin")
             ]
           }},
          fn -> PlacesAdapter.geocode("Alexanderstraße 1", language_code: "de") end
        )

      assert {:ok, %{lat: 52.5215, lng: 13.405, formatted_address: "Alexanderstraße 1, 10178 Berlin"}} =
               result

      req = captured_request()
      assert req.headers["x-goog-fieldmask"] == [@geocode_mask]
      assert req.options.receive_timeout == 5_000
      assert %{"textQuery" => "Alexanderstraße 1", "pageSize" => 1, "languageCode" => "de"} =
               decode_body()

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :start], %{system_time: _},
                       %{operation: :geocode}}

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :stop], %{duration_ms: _},
                       %{operation: :geocode, status: :ok}}
    end

    test "a place without coordinates is address_not_found" do
      assert {:error, :address_not_found} =
               with_adapter(
                 {:ok, %{"places" => [%{"id" => "p1", "formattedAddress" => "somewhere"}]}},
                 fn -> PlacesAdapter.geocode("somewhere") end
               )
    end

    test "an empty places list is address_not_found" do
      assert {:error, :address_not_found} =
               with_adapter({:ok, %{"places" => []}}, fn -> PlacesAdapter.geocode("nowhere") end)
    end

    test "a Google error envelope maps to {:upstream, status, message}" do
      assert {:error, {:upstream, 429, "quota exceeded"}} =
               with_adapter(
                 {:http_error, 429, %{"error" => %{"code" => 429, "message" => "quota exceeded"}}},
                 fn -> PlacesAdapter.geocode("somewhere") end
               )

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :stop], _, %{
                        operation: :geocode,
                        status: :upstream
                      }}
    end

    test "a Google error without a message falls back to the generic text" do
      assert {:error, {:upstream, 403, "upstream error"}} =
               with_adapter(
                 {:http_error, 403, %{"error" => %{"code" => 403}}},
                 fn -> PlacesAdapter.geocode("somewhere") end
               )
    end

    test "a transport failure maps to upstream_unavailable" do
      assert {:error, :upstream_unavailable} =
               with_adapter(
                 {:raise, %Req.TransportError{reason: :nxdomain}},
                 fn -> PlacesAdapter.geocode("somewhere") end
               )

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :stop], _, %{
                        operation: :geocode,
                        status: :unavailable
                      }}
    end

    test "an adapter crash is re-raised with the exception telemetry event" do
      assert %RuntimeError{message: "kaboom"} =
               with_adapter({:raise!, RuntimeError.exception("kaboom")}, fn ->
                 assert_raise RuntimeError, "kaboom", fn -> PlacesAdapter.geocode("somewhere") end
               end)

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :exception], _,
                       %{operation: :geocode, kind: :error, reason: %RuntimeError{}}}
    end

    test "an adapter throw surfaces with the exception telemetry event" do
      assert catch_throw(with_adapter({:throw, :boom}, fn -> PlacesAdapter.geocode("x") end)) ==
               :boom

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :exception], _,
                       %{operation: :geocode, kind: :throw, reason: :boom}}
    end

    test "receive_timeout override reaches the request options" do
      Application.put_env(:pharmacy_app, :places_receive_timeout, 1_234)

      with_adapter({:ok, %{"places" => []}}, fn -> PlacesAdapter.geocode("somewhere") end)

      assert captured_request().options.receive_timeout == 1_234
    end
  end

  # -- search_nearby/4 ---------------------------------------------------------

  describe "search_nearby/4" do
    test "happy path: translates places with routing summaries and hours" do
      body = %{
        "places" => [
          Map.merge(@wire_place, %{
            "currentOpeningHours" => %{
              "openNow" => true,
              "weekdayDescriptions" => ["Mon: 08:00–20:00"],
              "nextCloseTime" => "2026-11-21T16:00:00+02:00"
            },
            "nationalPhoneNumber" => "030 123456",
            "utcOffsetMinutes" => 120
          })
        ],
        "routingSummaries" => [
          %{"legs" => [%{"distanceMeters" => 210, "duration" => "180s"}]}
        ]
      }

      assert {:ok, [pharmacy]} =
               with_adapter({:ok, body}, fn ->
                 PlacesAdapter.search_nearby(52.52, 13.405, 1000, language_code: "de")
               end)

      assert pharmacy.id == "p1"
      assert pharmacy.display_name == "Apotheke Mitte"
      assert pharmacy.address == "Friedrichstraße 1, 10117 Berlin"
      assert pharmacy.lat == 52.5215 and pharmacy.lng == 13.405
      assert pharmacy.distance_m == nil
      assert pharmacy.open_now == true
      assert pharmacy.opening_hours == ["Mon: 08:00–20:00"]
      # nextCloseTime decodes to UTC (14:00Z); the place offset restores local 16:00.
      assert pharmacy.closes_at == "16:00"
      assert pharmacy.phone_number == "030 123456"
      assert pharmacy.walk_distance_m == 210
      assert pharmacy.walk_duration_s == 180

      req = captured_request()
      assert req.headers["x-goog-fieldmask"] == [@nearby_mask]
      assert req.options.receive_timeout == 5_000

      wire = decode_body()
      assert wire["includedPrimaryTypes"] == ["pharmacy"]
      assert wire["languageCode"] == "de"
      assert wire["rankPreference"] == "DISTANCE"
      assert wire["maxResultCount"] == 20
      assert wire["locationRestriction"]["circle"]["center"] == %{
               "latitude" => 52.52,
               "longitude" => 13.405
             }

      assert wire["locationRestriction"]["circle"]["radius"] == 1000
      assert wire["routingParameters"]["origin"]["latitude"] == 52.52
      assert wire["routingParameters"]["travelMode"] == "WALK"

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :start], _,
                       %{operation: :search_nearby}}

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :stop], _,
                       %{operation: :search_nearby, status: :ok}}
    end

    test "an empty response maps to an empty list" do
      assert {:ok, []} =
               with_adapter({:ok, %{}}, fn -> PlacesAdapter.search_nearby(52.52, 13.405, 1000) end)
    end

    test "a Google error envelope maps to {:upstream, status, message}" do
      assert {:error, {:upstream, 500, "internal error"}} =
               with_adapter(
                 {:http_error, 500, %{"error" => %{"code" => 500, "message" => "internal error"}}},
                 fn -> PlacesAdapter.search_nearby(52.52, 13.405, 1000) end
               )

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :stop], _, %{
                        operation: :search_nearby,
                        status: :upstream
                      }}
    end

    test "a transport failure maps to upstream_unavailable" do
      assert {:error, :upstream_unavailable} =
               with_adapter(
                 {:raise, %Req.TransportError{reason: :econnrefused}},
                 fn -> PlacesAdapter.search_nearby(52.52, 13.405, 1000) end
               )

      assert_received {:telemetry, [:pharmacy_app, :places, :request, :stop], _, %{
                        operation: :search_nearby,
                        status: :unavailable
                      }}
    end
  end
end
