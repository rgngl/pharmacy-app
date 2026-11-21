defmodule PharmacyAppWeb.PharmaciesControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint PharmacyAppWeb.Endpoint

  setup do
    on_exit(fn -> Application.delete_env(:pharmacy_app, :service_opts) end)
    :ok
  end

  defp set_client(result) do
    Application.put_env(:pharmacy_app, :service_opts, client: PharmacyApp.TestClient)
    Application.put_env(:pharmacy_app, :test_client_fn, fn _lat, _lng, _r -> result end)
  end

  test "renders 200 with a JSON list of pharmacy maps" do
    set_client({:ok, [%Googly.Places.Model.GoogleMapsPlacesV1Place{
      id: "place-1",
      display_name: %Googly.Places.Model.GoogleTypeLocalizedText{text: "Apotheke"},
      formatted_address: "Friedrichstraße 1",
      location: %Googly.Places.Model.GoogleTypeLatLng{latitude: 52.52, longitude: 13.405}
    }]})

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
end
