defmodule PharmacyApp.Pharmacies.CacheTest do
  use ExUnit.Case, async: false

  alias PharmacyApp.Pharmacies.Cache

  setup do
    case GenServer.whereis(Cache) do
      nil -> start_supervised!(Cache)
      _pid -> :ok
    end

    :ok
  end

  test "put/get round trip" do
    key = Cache.key(10.5, 20.5, 300)
    :ok = Cache.put(key, ["a", "b"])
    assert Cache.get(key) == {:ok, ["a", "b"]}
  end

  test "miss for unseen key" do
    assert Cache.get(Cache.key(1.0, 2.0, 100)) == :miss
  end

  test "ttl expiry: expired entries read as miss" do
    key = Cache.key(5.0, 5.0, 100)
    Cache.put(key, :value, 1)
    Process.sleep(5)
    assert Cache.get(key) == :miss
  end

  test "eviction sweep removes expired entries" do
    key = Cache.key(6.0, 6.0, 100)
    Cache.put(key, :value, 5_000)

    now = System.system_time(:millisecond)
    :ets.insert(:pharmacy_cache, {Cache.key(7.0, 7.0, 100), :stale, now - 10_000})

    Process.sleep(350)

    assert Cache.get(Cache.key(7.0, 7.0, 100)) == :miss
    # not yet expired
    assert Cache.get(key) == {:ok, :value}
  end
end
