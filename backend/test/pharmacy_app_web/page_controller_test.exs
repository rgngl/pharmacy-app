defmodule PharmacyAppWeb.PageControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint PharmacyAppWeb.Endpoint

  setup do
    on_exit(fn ->
      Application.delete_env(:pharmacy_app, :service_opts)
      Application.delete_env(:pharmacy_app, :test_client_fn)
      Application.delete_env(:pharmacy_app, :test_geocoder_fn)
    end)

    # Geocode cache is a global ETS table; entries would leak across tests
    # and satisfy later requests without hitting the geocoder.
    if :ets.whereis(:pharmacy_cache) != :undefined, do: :ets.delete_all_objects(:pharmacy_cache)
    :ok
  end

  defp put_service_opt(key, value) do
    opts = Application.get_env(:pharmacy_app, :service_opts, [])
    Application.put_env(:pharmacy_app, :service_opts, Keyword.put(opts, key, value))
  end

  defp set_client(result) do
    put_service_opt(:client, PharmacyApp.TestClient)
    Application.put_env(:pharmacy_app, :test_client_fn, fn _lat, _lng, _r, _opts -> result end)
  end

  defp set_geocoder(result) do
    put_service_opt(:geocoder, PharmacyApp.TestClient)
    Application.put_env(:pharmacy_app, :test_geocoder_fn, fn _address, _opts -> result end)
  end

  # Adapter-level output per the contract: %Pharmacy{} WITHOUT distance_m.
  defp pharmacy(id \\ "place-1") do
    %PharmacyApp.Pharmacies.Pharmacy{
      id: id,
      display_name: "Apotheke",
      address: "Friedrichstraße 1",
      lat: 52.5215,
      lng: 13.405
    }
  end

  test "renders a form-only page with no search input" do
    conn = get(build_conn(), "/")
    html = html_response(conn, 200)

    assert html =~ "Enter an address above, or use your location"
    # No radius chips render on the form-only page (the inline stylesheet
    # mentions .radius-label, so assert on link markup instead).
    refute html =~ ~s(href="/?)
    refute html =~ "Apotheke"
    refute html =~ "Search results by Google Maps"
  end

  test "address search renders resolved address, results, attribution, and q chips" do
    set_geocoder({:ok, %{lat: 52.52, lng: 13.405, formatted_address: "Alexanderplatz, Berlin"}})
    set_client({:ok, [pharmacy()]})

    conn = get(build_conn(), "/", q: "Alexanderplatz, Berlin", radius_m: "2000")
    html = html_response(conn, 200)

    assert html =~ "Showing pharmacies near Alexanderplatz, Berlin"
    assert html =~ "Apotheke"
    assert html =~ "Search results by Google Maps"
    assert html =~ ~s(translate="no")
    assert html =~ "within 2000 m"

    # Chips follow the effective address origin: q kept, coords dropped.
    # (The inline geolocation script mentions ?lat=, so match values.)
    assert html =~ "q=Alexanderplatz"
    assert html =~ "radius_m=500"
    refute html =~ "lat=52"

    # The 2000 m chip is active (the effective radius), others are not.
    assert html =~ ~s(class="chip active")
  end

  test "coordinate search renders chips keeping lat/lng" do
    set_client({:ok, [pharmacy()]})

    conn = get(build_conn(), "/", lat: "52.52", lng: "13.405", radius_m: "500")
    html = html_response(conn, 200)

    assert html =~ "Apotheke"
    assert html =~ "lat=52.52"
    assert html =~ "lng=13.405"
    refute html =~ "q="
    refute html =~ "Showing pharmacies near"
  end

  test "both coordinates and q: coordinates win and chips keep coords" do
    set_geocoder({:ok, %{lat: 0.0, lng: 0.0, formatted_address: "should not be used"}})
    set_client({:ok, [pharmacy()]})

    conn = get(build_conn(), "/", q: "Alexanderplatz", lat: "52.52", lng: "13.405")
    html = html_response(conn, 200)

    assert html =~ "Apotheke"
    assert html =~ "lat=52.52"
    assert html =~ "lng=13.405"
    refute html =~ "q=Alexanderplatz"
    refute html =~ "should not be used"
  end

  test "address without a geocode result renders the banner" do
    set_geocoder({:error, :address_not_found})

    conn = get(build_conn(), "/", q: "middle of nowhere")
    html = html_response(conn, 200)

    # The apostrophe is HTML-escaped in the rendered banner.
    assert html =~ "find an address matching"
    assert html =~ "middle of nowhere"
  end

  test "invalid params render inline errors without an upstream call" do
    Application.put_env(:pharmacy_app, :test_client_fn, fn _, _, _, _ ->
      send(self(), {:client_called})
      {:ok, [pharmacy()]}
    end)

    conn = get(build_conn(), "/", lat: "999", lng: "13.405")
    html = html_response(conn, 200)

    assert html =~ "lat must be a number between -90 and 90"
    refute_received {:client_called}
  end

  test "radius is clamped to the domain maximum for display" do
    set_client({:ok, [pharmacy()]})

    conn = get(build_conn(), "/", lat: "52.52", lng: "13.405", radius_m: "999999")
    html = html_response(conn, 200)

    assert html =~ "within 50000 m"
  end

  test "client-side upstream errors are mirrored with a banner" do
    set_client({:error, {:upstream, 403, "API key not valid"}})

    conn = get(build_conn(), "/", lat: "52.52", lng: "13.405")

    assert conn.status == 403
    assert html_response(conn, 403) =~ "Upstream error (403): API key not valid"
  end

  test "server-side upstream errors render a 502 banner" do
    set_client({:error, {:upstream, 500, "boom"}})

    conn = get(build_conn(), "/", lat: "52.52", lng: "13.405")

    assert conn.status == 502
    assert html_response(conn, 502) =~ "Upstream error (500): boom"
  end

  test "non-scalar input renders 200 with inline errors" do
    conn = get(build_conn(), "/", lat: %{a: 1}, lng: "13.405")

    assert conn.status == 200
    html = html_response(conn, 200)
    assert html =~ "lat must be a number between -90 and 90"
    # Not treated as a search: no results section.
    refute html =~ "Apotheke"
  end

  test "upstream unavailable renders a 502 banner" do
    set_client({:error, :upstream_unavailable})

    conn = get(build_conn(), "/", lat: "52.52", lng: "13.405")

    assert conn.status == 502
    assert html_response(conn, 502) =~ "Upstream unavailable"
  end
end
