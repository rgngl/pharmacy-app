defmodule PharmacyApp.Pharmacies.Service do
  @moduledoc """
  Orchestration only: validate → cache → client → map/filter/sort → cache.
  No business rules or HTTP here.
  """

  alias PharmacyApp.Pharmacies
  alias PharmacyApp.Pharmacies.{Cache, PlacesAdapter}

  @doc """
  `opts` accepts `:client` (default `PlacesAdapter`) and `:cache`
  (default `Cache`). Client returns `{:ok, places}` or
  `{:error, {:upstream, status, msg}} | {:error, :upstream_unavailable}`.
  Cache must expose `get(key)` and `put(key, value)`.
  """
  def search(params, opts \\ []) do
    client = Keyword.get(opts, :client, PlacesAdapter)
    cache = Keyword.get(opts, :cache, Cache)

    case Pharmacies.validate_params(params) do
      {:error, issues} -> {:error, {:invalid_params, issues}}
      {:ok, validated} -> cached_or_fetch(validated, client, cache)
    end
  end

  defp cached_or_fetch(validated, client, cache) do
    key = Cache.key(validated.lat, validated.lng, validated.radius_m)

    case cache.get(key) do
      {:ok, value} -> {:ok, value}
      _ -> miss(validated, client, cache)
    end
  end

  defp miss(validated, client, cache) do
    with {:ok, google_places} <- call_client(client, validated),
         point = {validated.lat, validated.lng},
         pharmacies <-
           google_places
           |> Enum.map(&Pharmacies.from_google(&1, point))
           |> Pharmacies.filter(validated.radius_m)
           |> Pharmacies.sort() do
      cache.put(Cache.key(validated.lat, validated.lng, validated.radius_m), pharmacies)
      {:ok, pharmacies}
    end
  end

  defp call_client(client, validated) when is_function(client, 3),
    do: client.(validated.lat, validated.lng, validated.radius_m)

  defp call_client(client, validated),
    do: client.search_nearby(validated.lat, validated.lng, validated.radius_m)
end
