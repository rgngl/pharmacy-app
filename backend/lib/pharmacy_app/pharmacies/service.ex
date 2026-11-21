defmodule PharmacyApp.Pharmacies.Service do
  @moduledoc """
  Orchestration only: validate → cache → client → map/filter/sort → cache.
  No business rules or HTTP here.
  """

  alias PharmacyApp.Pharmacies
  alias PharmacyApp.Pharmacies.{Cache, PlacesAdapter}

  @doc """
  `opts` accepts `:client` (default `PlacesAdapter`) and `:cache`
  (default `Cache`). Client is called with
  `(lat, lng, radius_m, [language_code: code])` and returns
  `{:ok, places}` or
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

  @doc """
  Resolves a free-form address to coordinates (geocode result cached), then
  runs the same pipeline as `search/2`.

  `opts` accepts everything `search/2` does, plus:

  * `:geocoder` (default `PlacesAdapter`) — called with
    `(address, [language_code: code])`, returning
    `{:ok, %{lat, lng, formatted_address}}`, `{:error, :address_not_found}`,
    or the upstream error shapes
  * `:radius_m` / `:language_code` — forwarded into the downstream search

  Returns `{:ok, %{lat: float, lng: float, formatted_address: String.t,
  pharmacies: [%Pharmacy{}]}}`, `{:error, :address_not_found}`, or the
  `search/2` error shapes.
  """
  def search_by_address(address, opts \\ []) do
    geocoder = Keyword.get(opts, :geocoder, PlacesAdapter)
    cache = Keyword.get(opts, :cache, Cache)

    with {:ok, validated} <- validate_downstream(opts),
         {:ok, resolved} <- cached_geocode(geocoder, cache, address, validated.language_code) do
      case search(
             %{
               lat: resolved.lat,
               lng: resolved.lng,
               radius_m: validated.radius_m,
               language_code: validated.language_code
             },
             opts
           ) do
        {:ok, pharmacies} ->
          {:ok, Map.put(resolved, :pharmacies, pharmacies)}

        error ->
          error
      end
    end
  end

  # Validates radius/language before any upstream call so bad query params
  # fail fast without spending a Text Search. lat/lng are placeholder-checked
  # here and replaced by the geocoded coordinates.
  defp validate_downstream(opts) do
    case Pharmacies.validate_params(%{
           lat: 0.0,
           lng: 0.0,
           radius_m: Keyword.get(opts, :radius_m),
           language_code: Keyword.get(opts, :language_code)
         }) do
      {:ok, validated} -> {:ok, validated}
      {:error, issues} -> {:error, {:invalid_params, issues}}
    end
  end

  defp cached_geocode(geocoder, cache, address, language_code) do
    key = Cache.geocode_key(address, language_code)

    case cache.get(key) do
      {:ok, resolved} ->
        {:ok, resolved}

      _ ->
        case geocoder.geocode(address, language_code: language_code) do
          {:ok, resolved} ->
            cache.put(key, resolved)
            {:ok, resolved}

          error ->
            error
        end
    end
  end

  defp cached_or_fetch(validated, client, cache) do
    key = Cache.key(validated.lat, validated.lng, validated.radius_m, validated.language_code)

    case cache.get(key) do
      {:ok, value} -> {:ok, value}
      _ -> miss(validated, client, cache)
    end
  end

  defp miss(validated, client, cache) do
    with {:ok, client_result} <- call_client(client, validated),
         point = {validated.lat, validated.lng},
         {google_places, summaries} = split_result(client_result),
         pharmacies <-
           google_places
           |> Enum.zip(summaries)
           |> Enum.map(fn {place, summary} ->
             place |> Pharmacies.from_google(point) |> Pharmacies.put_walk(summary)
           end)
           |> Enum.reject(&is_nil/1)
           |> Pharmacies.filter(validated.radius_m)
           |> Pharmacies.sort() do
      cache.put(
        Cache.key(validated.lat, validated.lng, validated.radius_m, validated.language_code),
        pharmacies
      )

      {:ok, pharmacies}
    end
  end

  # The adapter returns `{:ok, %{places:, routing_summaries:}}`; plain
  # lists are still accepted so injected fake clients need no summaries.
  # Summaries are padded to the place count: Enum.zip would otherwise
  # truncate when the upstream returns fewer (or a fake returns none).
  defp split_result(%{places: places, routing_summaries: summaries}) do
    places = places || []
    {places, Enum.take(summaries || [], length(places)) ++ List.duplicate(nil, length(places))}
  end

  defp split_result(places) when is_list(places), do: {places, List.duplicate(nil, length(places))}

  defp call_client(client, validated) when is_function(client, 4),
    do:
      client.(validated.lat, validated.lng, validated.radius_m,
        language_code: validated.language_code
      )

  defp call_client(client, validated),
    do:
      client.search_nearby(validated.lat, validated.lng, validated.radius_m,
        language_code: validated.language_code
      )
end
