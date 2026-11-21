defmodule PharmacyApp.Pharmacies.ServiceTest do
  use ExUnit.Case, async: false

  alias PharmacyApp.Pharmacies.Pharmacy
  alias PharmacyApp.Pharmacies.Service

  # In-memory fake cache with counters for the geocode-cache tests.
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

  # Fakes follow the adapter contract: %Pharmacy{} structs without
  # distance_m (the service fills it per request).
  def pharmacy(id, lat, lng) do
    %Pharmacy{id: id, display_name: id, address: "addr", lat: lat, lng: lng}
  end

  test "fills distance, filters and sorts the client's pharmacies" do
    # Client returns pharmacies without distance_m, in no particular
    # order. Offsets along latitude from the query point (52.52, 13.405):
    # ~167 m, ~367 m, ~1.11 km.
    set_client_result(
      {:ok,
       [
         pharmacy("Mid", 52.5233, 13.405),
         pharmacy("Far", 52.53, 13.405),
         pharmacy("Near", 52.5215, 13.405)
       ]}
    )

    assert {:ok, result} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 1000},
               client: client_stub(),
               cache: FakeCache
             )

    assert Enum.map(result, & &1.display_name) == ["Near", "Mid"]

    near = Enum.find(result, &(&1.display_name == "Near"))
    mid = Enum.find(result, &(&1.display_name == "Mid"))
    # haversine returns floats; integer ranges reject floats under `in`
    assert near.distance_m >= 150 and near.distance_m <= 185
    assert mid.distance_m >= 350 and mid.distance_m <= 385
    assert near.distance_m < mid.distance_m

    assert_received {:client_called, 52.52, 13.405, 1000, nil}
  end

  test "same origin, different radii: each request returns its own results, in both orders" do
    # ~367 m from the origin: inside radius 500, outside radius 200.
    set_client_result({:ok, [pharmacy("Mid", 52.5233, 13.405)]})
    stub = client_stub()

    assert {:ok, wide} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 500},
               client: stub,
               cache: FakeCache
             )

    assert Enum.map(wide, & &1.display_name) == ["Mid"]

    assert {:ok, narrow} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 200},
               client: stub,
               cache: FakeCache
             )

    assert narrow == []

    # Reversed order with a fresh stub: the narrow request must not
    # inherit the wider request's (or anyone's) result set.
    assert {:ok, []} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 200},
               client: client_stub(),
               cache: FakeCache
             )

    set_client_result({:ok, [pharmacy("Mid", 52.5233, 13.405)]})

    assert {:ok, wide_again} =
             Service.search(%{lat: 52.52, lng: 13.405, radius_m: 500},
               client: client_stub(),
               cache: FakeCache
             )

    assert Enum.map(wide_again, & &1.display_name) == ["Mid"]

    # Every request hit the client: no cross-request reuse anywhere.
    assert_received {:client_called, 52.52, 13.405, 500, nil}
    assert_received {:client_called, 52.52, 13.405, 200, nil}
    assert_received {:client_called, 52.52, 13.405, 200, nil}
    assert_received {:client_called, 52.52, 13.405, 500, nil}
  end

  test "two origins in the same grid cell are independent" do
    # 52.52049 and 52.52051 both rounded into the same 0.001° cell under
    # the removed grid-cell key, which reused results across them.
    set_client_result({:ok, [pharmacy("A-near", 52.5206, 13.405)]})
    stub = client_stub()

    assert {:ok, result_a} =
             Service.search(%{lat: 52.52049, lng: 13.405, radius_m: 500},
               client: stub,
               cache: FakeCache
             )

    set_client_result({:ok, [pharmacy("B-near", 52.5212, 13.405)]})

    assert {:ok, result_b} =
             Service.search(%{lat: 52.52051, lng: 13.405, radius_m: 500},
               client: stub,
               cache: FakeCache
             )

    assert Enum.map(result_a, & &1.id) == ["A-near"]
    assert Enum.map(result_b, & &1.id) == ["B-near"]
    assert_received {:client_called, 52.52049, _, _, _}
    assert_received {:client_called, 52.52051, _, _, _}
  end

  test "language_code is forwarded to the client" do
    set_client_result({:ok, []})

    {:ok, _} =
      Service.search(%{lat: 10.0, lng: 20.0, radius_m: 500, language_code: "fr-CA"},
        client: client_stub(),
        cache: FakeCache
      )

    assert_received {:client_called, 10.0, 20.0, 500, "fr-CA"}
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
    set_client_result({:ok, [pharmacy("Near", 52.5215, 13.405), pharmacy("Far", 52.53, 13.405)]})

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

  test "address search: missing radius defaults to 1000" do
    set_client_result({:ok, []})

    {:ok, _} =
      Service.search_by_address("A",
        geocoder: FakeGeocoder,
        client: client_stub(),
        cache: FakeCache
      )

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

  test "address search: invalid geocoded coordinates fail before the client" do
    Process.put(:geocoder_result, {:ok, %{lat: 200, lng: 0, formatted_address: "x"}})

    assert {:error, {:invalid_params, ["lat must be a number between -90 and 90"]}} =
             Service.search_by_address("x",
               geocoder: FakeGeocoder,
               client: client_stub(),
               cache: FakeCache
             )

    assert_received {:geocode_called, "x", nil}
    refute_received {:client_called, _, _, _, _}
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
    refute_received {:client_called, _, _, _, _}
  end
end
