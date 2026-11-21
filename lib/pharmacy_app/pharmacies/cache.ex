defmodule PharmacyApp.Pharmacies.Cache do
  @moduledoc """
  Default cache backend: a public ETS table with a GenServer that sweeps
  expired entries. Safe to start as a supervised child.
  """
  use GenServer

  @table :pharmacy_cache
  @ttl :timer.seconds(60)
  @sweep_interval Application.compile_env(:pharmacy_app, :cache_sweep_interval, :timer.seconds(10))

  def child_spec(_arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Key: a ~100m lat/lng grid cell plus a radius bucket and language tag.
  The language is part of the key because opening hours are returned as
  pre-formatted text in the requested locale.
  """
  def key(lat, lng, radius_m, language \\ nil) do
    {round(lat / 0.001), round(lng / 0.001), round(radius_m / 100), language}
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if expires_at > now_ms(), do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  def put(key, value, ttl \\ @ttl) do
    :ets.insert(@table, {key, value, now_ms() + ttl})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl GenServer
  def init(_state) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, []}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    now = now_ms()
    :ets.select_delete(@table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}])
    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  defp now_ms, do: System.system_time(:millisecond)
end
