defmodule PharmacyApp.Pharmacies.ServiceTest do
  use ExUnit.Case, async: false

  alias PharmacyApp.Pharmacies
  alias PharmacyApp.Pharmacies.Service

  # In-memory fake cache with counters for the "cache hit skips client" test.
  defmodule FakeCache do
    @ets :service_test_cache

    def start do
      :ets.new(@ets, [:named_table, :public, read_concurrency: true])
    end

    def get(key) do
      case :ets.lookup(@ets, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :miss
      end
    end

    def put(key, value) do
      :ets.insert(@ets, {key, value})
      :ok
    end

    def clear, do: :ets.delete_all_objects(@ets)
  end

  def client_stub do
    parent = self()

    fn lat, lng, radius_m, opts ->
      send(parent, {:client_called, lat, lng, radius_m, opts[:language_code]})
      get_client_result()
    end
  end

  def get_client_result, do: Process.get(:client_result)
  def set_client_result(result), do: Process.put(:client_result, result)

  defmodule FakeGeocoder do
    # Sends {:geocode_called, address, language} to the test process and
    # returns what the test stored under :geocoder_result.
    def geocode(address, opts) do
      send(Process.get(:geocoder_parent), {:geocode_called, address, opts[:language_code]})
      Process.get(:geocoder_result)
    end
  end

  setup do
    FakeCache.start()
    FakeCache.clear()
    set_client_result({:ok, []})
    Process.put(:geocoder_parent, self())
    Process.put(:geocoder_result, {:ok, %{lat: 52.52, lng: 13.405, formatted_address: "Berlin"}})
    :ok
  end

  test "happy path: maps, filters, sorts and caches" do
    # Client returns Google places; service maps them with from_google/2.
    # Offsets along latitude from the query point (52.52, 13.405):
    # ~167 m, ~367 m, ~1.11 km.
    set_client_result(
      {:ok,
       [
         google_place(52.5233, 13.405, "Mid"),
         google_place(52.53, 13.405, "Far"),
         google_place(52.5215, 13.405, "Near")
       ]}
    )

    assert {:ok, result} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 1000},
               client: client_stub(),
               cache: FakeCache
             )

    assert Enum.map(result, & &1.display_name) == ["Near", "Mid"]
    assert_received {:client_called, 52.52, 13.405, 1000, nil}

    # Cached and sorted
    assert {:ok, cached} = FakeCache.get(Pharmacies.Cache.key(52.52, 13.405, 1000))
    assert Enum.map(cached, & &1.display_name) == ["Near", "Mid"]
  end

  test "drops places without location instead of crashing" do
    # Google omits `location` when it is missing from the field mask; the
    # service must skip such places rather than raise in haversine_m/4.
    set_client_result(
      {:ok,
       [
         google_place(52.5215, 13.405, "Near"),
         %Googly.Places.Model.GoogleMapsPlacesV1Place{id: "no-location"}
       ]}
    )

    assert {:ok, result} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 1000},
               client: client_stub(),
               cache: FakeCache
             )

    assert Enum.map(result, & &1.id) == ["Near"]
  end

  def google_place(lat, lng, name) do
    %Googly.Places.Model.GoogleMapsPlacesV1Place{
      id: name,
      display_name: %Googly.Places.Model.GoogleTypeLocalizedText{text: name},
      formatted_address: "addr",
      location: %Googly.Places.Model.GoogleTypeLatLng{latitude: lat, longitude: lng}
    }
  end

  test "cache hit skips the client" do
    key = Pharmacies.Cache.key(10.0, 20.0, 500)
    FakeCache.put(key, [%Pharmacies{id: "cached", distance_m: 5}])

    assert {:ok, result} =
             Service.search(%{lat: 10.0, lng: 20.0, radius_m: 500},
               client: client_stub(),
               cache: FakeCache
             )

    assert Enum.map(result, & &1.id) == ["cached"]
    refute_received {:client_called, _, _, _, _}
  end

  test "language_code is forwarded to the client and part of the cache key" do
    client = client_stub()

    set_client_result({:ok, []})

    {:ok, _} =
      Service.search(%{lat: 10.0, lng: 20.0, radius_m: 500, language_code: "fr-CA"},
        client: client,
        cache: FakeCache
      )

    assert_received {:client_called, 10.0, 20.0, 500, "fr-CA"}

    # Same query, different locale: hours text differs, so it must be a miss.
    set_client_result({:ok, []})

    {:ok, _} =
      Service.search(%{lat: 10.0, lng: 20.0, radius_m: 500, language_code: "de"},
        client: client,
        cache: FakeCache
      )

    assert_received {:client_called, 10.0, 20.0, 500, "de"}

    # Same locale again: cache hit, no second upstream call.
    {:ok, _} =
      Service.search(%{lat: 10.0, lng: 20.0, radius_m: 500, language_code: "de"},
        client: client,
        cache: FakeCache
      )

    refute_received {:client_called, _, _, _, _}
  end

  test "invalid language_code fails validation without touching the client" do
    assert {:error, {:invalid_params, issues}} =
             Service.search(%{lat: 10.0, lng: 20.0, radius_m: 500, language_code: "not a tag!"})

    assert issues == ["language_code must be a BCP-47 language tag"]
    refute_received {:client_called, _, _, _, _}
  end

  test "invalid params fail fast without touching the client" do
    assert {:error, {:invalid_params, issues}} =
             Service.search(%{lat: 200, lng: 0},
               client: client_stub(),
               cache: FakeCache
             )

    assert issues == ["lat must be a number between -90 and 90"]
    refute_received {:client_called, _, _, _, _}
  end

  test "upstream errors pass through" do
    set_client_result({:error, {:upstream, 403, "denied"}})

    assert {:error, {:upstream, 403, "denied"}} =
             Service.search(%{lat: 0, lng: 0},
               client: client_stub(),
               cache: FakeCache
             )

    set_client_result({:error, :upstream_unavailable})

    assert {:error, :upstream_unavailable} =
             Service.search(%{lat: 0, lng: 0},
               client: client_stub(),
               cache: FakeCache
             )
  end

  test "address search: geocodes then searches with the resolved point" do
    set_client_result(
      {:ok, [google_place(52.5215, 13.405, "Near"), google_place(52.53, 13.405, "Far")]}
    )

    assert {:ok, %{lat: 52.52, lng: 13.405, formatted_address: "Berlin", pharmacies: result}} =
             Service.search_by_address("Alexanderplatz, Berlin",
               radius_m: 1000,
               geocoder: FakeGeocoder,
               client: client_stub(),
               cache: FakeCache
             )

    assert Enum.map(result, & &1.display_name) == ["Near"]
    assert_received {:geocode_called, "Alexanderplatz, Berlin", nil}
    assert_received {:client_called, 52.52, 13.405, 1000, nil}
  end

  test "address search: geocode result is cached per address and language" do
    set_client_result({:ok, []})

    {:ok, _} =
      Service.search_by_address("A",
        geocoder: FakeGeocoder,
        client: client_stub(),
        cache: FakeCache
      )

    {:ok, _} =
      Service.search_by_address("A",
        geocoder: FakeGeocoder,
        client: client_stub(),
        cache: FakeCache
      )

    assert_received {:geocode_called, "A", nil}
    refute_received {:geocode_called, _, _}

    # Different locale → different cache key → geocode runs again.
    {:ok, _} =
      Service.search_by_address("A",
        language_code: "de",
        geocoder: FakeGeocoder,
        client: client_stub(),
        cache: FakeCache
      )

    assert_received {:geocode_called, "A", "de"}
  end

  test "address search: not found stops before the pharmacy client" do
    Process.put(:geocoder_result, {:error, :address_not_found})

    assert {:error, :address_not_found} =
             Service.search_by_address("nowhere",
               geocoder: FakeGeocoder,
               client: client_stub(),
               cache: FakeCache
             )

    assert_received {:geocode_called, "nowhere", nil}
    refute_received {:client_called, _, _, _, _}
  end

  test "address search: upstream geocode errors pass through" do
    Process.put(:geocoder_result, {:error, {:upstream, 403, "denied"}})

    assert {:error, {:upstream, 403, "denied"}} =
             Service.search_by_address("x",
               geocoder: FakeGeocoder,
               client: client_stub(),
               cache: FakeCache
             )

    refute_received {:client_called, _, _, _, _}
  end

  test "address search: invalid language fails validation without geocoding" do
    assert {:error, {:invalid_params, ["language_code must be a BCP-47 language tag"]}} =
             Service.search_by_address("x",
               language_code: "not a tag!",
               geocoder: FakeGeocoder,
               client: client_stub(),
               cache: FakeCache
             )

    refute_received {:geocode_called, _, _}
  end
end
