defmodule PharmacyAppWeb.PharmaciesControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint PharmacyAppWeb.Endpoint

  setup do
    on_exit(fn ->
      Application.delete_env(:pharmacy_app, :service_opts)
      Application.delete_env(:pharmacy_app, :test_geocoder_fn)
    end)

    # Cache is a global ETS table with a 60s TTL; entries would leak across
    # tests and satisfy later requests without hitting the client.
    if :ets.whereis(:pharmacy_cache) != :undefined, do: :ets.delete_all_objects(:pharmacy_cache)
    :ok
  end

  defp set_client(result) do
    put_service_opt(:client, PharmacyApp.TestClient)
    Application.put_env(:pharmacy_app, :test_client_fn, fn _lat, _lng, _r, _opts -> result end)
  end

  defp set_client_capture(parent, result) do
    put_service_opt(:client, PharmacyApp.TestClient)

    Application.put_env(:pharmacy_app, :test_client_fn, fn _lat, _lng, _r, opts ->
      send(parent, {:client_opts, opts})
      result
    end)
  end

  # Service opts accumulate across helpers so a test can stub both the
  # geocoder and the client; the setup hook clears the env afterwards.
  defp put_service_opt(key, value) do
    opts = Application.get_env(:pharmacy_app, :service_opts, [])
    Application.put_env(:pharmacy_app, :service_opts, Keyword.put(opts, key, value))
  end

  test "forwards client Accept-Language to the upstream" do
    set_client_capture(self(), {:ok, []})

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("accept-language", "de-DE,de;q=0.9,en;q=0.8")
      |> get("/api/pharmacies", lat: "52.52", lng: "13.405", radius_m: "1000")

    assert conn.status == 200
    assert_received {:client_opts, opts}
    assert opts[:language_code] == "de-DE"
  end

  test "missing Accept-Language sends no language code" do
    set_client_capture(self(), {:ok, []})

    conn = get(build_conn(), "/api/pharmacies", lat: "52.52", lng: "13.405", radius_m: "1000")

    assert conn.status == 200
    assert_received {:client_opts, opts}
    assert opts[:language_code] == nil
  end

  test "renders 200 with a JSON list of pharmacy maps" do
    set_client(
      {:ok,
       [
         %Googly.Places.Model.GoogleMapsPlacesV1Place{
           id: "place-1",
           display_name: %Googly.Places.Model.GoogleTypeLocalizedText{text: "Apotheke"},
           formatted_address: "Friedrichstraße 1",
           location: %Googly.Places.Model.GoogleTypeLatLng{latitude: 52.52, longitude: 13.405}
         }
       ]}
    )

    conn = get(build_conn(), "/api/pharmacies", lat: "52.52", lng: "13.405", radius_m: "1000")

    assert conn.status == 200
    assert conn.resp_body != ""
    [body] = Jason.decode!(conn.resp_body)

    assert body["id"] == "place-1"
    assert body["display_name"] == "Apotheke"
    assert body["address"] == "Friedrichstraße 1"
    assert body["distance_m"] >= 0 and body["distance_m"] <= 100
    refute Map.has_key?(body, "google_place")
  end

  test "renders 422 with issues on invalid params" do
    conn = get(build_conn(), "/api/pharmacies", lat: "999", lng: "13.405")

    assert conn.status == 422
    assert %{"errors" => issues} = Jason.decode!(conn.resp_body)
    assert is_list(issues)
    assert length(issues) >= 1
  end

  test "renders 422 for missing params" do
    conn = get(build_conn(), "/api/pharmacies", lng: "13.405")
    assert conn.status == 422
  end

  test "renders upstream status for client-side Google errors" do
    set_client({:error, {:upstream, 403, "API key not valid"}})
    conn = get(build_conn(), "/api/pharmacies", lat: "55.5", lng: "15.5", radius_m: "1000")

    assert conn.status == 403

    assert %{"errors" => [%{"status" => 403, "message" => "API key not valid"}]} =
             Jason.decode!(conn.resp_body)
  end

  test "renders 502 when upstream is unavailable" do
    set_client({:error, :upstream_unavailable})
    conn = get(build_conn(), "/api/pharmacies", lat: "60.1", lng: "25.1", radius_m: "1000")

    assert conn.status == 502
    assert %{"errors" => errors} = Jason.decode!(conn.resp_body)
    assert errors == ["upstream unavailable"]
  end

  defp set_geocoder(result) do
    put_service_opt(:geocoder, PharmacyApp.TestClient)
    Application.put_env(:pharmacy_app, :test_geocoder_fn, fn _address, _opts -> result end)
  end

  test "q geocodes the address then searches around it" do
    set_geocoder({:ok, %{lat: 52.52, lng: 13.405, formatted_address: "Berlin, Germany"}})

    set_client(
      {:ok,
       [
         %Googly.Places.Model.GoogleMapsPlacesV1Place{
           id: "place-1",
           display_name: %Googly.Places.Model.GoogleTypeLocalizedText{text: "Apotheke"},
           formatted_address: "Friedrichstraße 1",
           location: %Googly.Places.Model.GoogleTypeLatLng{latitude: 52.5215, longitude: 13.405}
         }
       ]}
    )

    conn = get(build_conn(), "/api/pharmacies", q: "Alexanderplatz, Berlin", radius_m: "1000")

    assert conn.status == 200
    [body] = Jason.decode!(conn.resp_body)
    assert body["id"] == "place-1"
    # Distance is computed from the geocoded point, not the raw query.
    # Place is ~167 m north of the geocoded point.
    assert body["distance_m"] >= 0 and body["distance_m"] <= 200
  end

  test "q with no geocode result renders 404" do
    set_geocoder({:error, :address_not_found})
    conn = get(build_conn(), "/api/pharmacies", q: "middle of nowhere")

    assert conn.status == 404
    assert %{"errors" => ["address not found"]} = Jason.decode!(conn.resp_body)
  end

  test "explicit lat/lng win over q without geocoding" do
    set_geocoder({:ok, %{lat: 0.0, lng: 0.0, formatted_address: "should not be used"}})
    set_client_capture(self(), {:ok, []})

    conn =
      get(build_conn(), "/api/pharmacies", q: "Alexanderplatz", lat: "52.52", lng: "13.405")

    assert conn.status == 200
    assert_received {:client_opts, opts}
    assert opts == [language_code: nil]
  end
end
