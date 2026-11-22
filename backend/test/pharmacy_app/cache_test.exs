defmodule PharmacyApp.Pharmacies.CacheTest do
  use ExUnit.Case, async: false

  alias PharmacyApp.Pharmacies.Cache

  setup do
    # A previous test may have deleted the table (rescue-branch tests). The
    # sweeper then crashes on the missing table and the supervisor's
    # restart recreates it via init/1; wait out that cycle before assuming
    # a usable cache. (No-ops when the table is intact.)
    wait_for_table(50)

    case GenServer.whereis(Cache) do
      nil -> start_supervised!(Cache)
      _pid -> :ok
    end

    wait_for_table(50)
    :ok
  end

  defp wait_for_table(0), do: flunk(":pharmacy_cache table never came back")

  defp wait_for_table(attempts) do
    if :ets.whereis(:pharmacy_cache) == :undefined do
      Process.sleep(10)
      wait_for_table(attempts - 1)
    end
  end

  test "put/get round trip" do
    key = Cache.geocode_key("Hauptstr. 5")
    :ok = Cache.put(key, %{lat: 52.5, lng: 13.4})
    assert Cache.get(key) == {:ok, %{lat: 52.5, lng: 13.4}}
  end

  test "miss for unseen key" do
    assert Cache.get(Cache.geocode_key("nowhere")) == :miss
  end

  test "ttl expiry: expired entries read as miss" do
    key = Cache.geocode_key("A")
    Cache.put(key, :value, 1)
    Process.sleep(5)
    assert Cache.get(key) == :miss
  end

  # The sweep must physically delete expired rows; a get/1 miss alone
  # would pass even if the GenServer never removed them (get treats an
  # expired row as a miss regardless). Compare table contents instead.
  test "eviction sweep deletes expired entries" do
    fresh_key = Cache.geocode_key("fresh")
    stale_key = Cache.geocode_key("stale")
    Cache.put(fresh_key, :value, 5_000)

    now = System.monotonic_time(:millisecond)
    :ets.insert(:pharmacy_cache, {stale_key, :stale, now - 10_000})

    # Test env sweep interval is 200 ms.
    Process.sleep(500)

    # not yet expired
    assert Cache.get(fresh_key) == {:ok, :value}
    # physically removed from the table, not just read as a miss
    assert :ets.lookup(:pharmacy_cache, stale_key) == []
  end

  test "get/1 fails open (miss) when the table is gone" do
    # The sweeper GenServer recreates the table on restart (supervised in
    # the application tree), so the very next line must already observe the
    # missing table.
    :ets.delete(:pharmacy_cache)

    assert Cache.get(Cache.geocode_key("gone")) == :miss
  end

  test "put/3 fails open (:ok) when the table is gone" do
    :ets.delete(:pharmacy_cache)

    assert Cache.put(Cache.geocode_key("gone"), :value) == :ok
  end
end
