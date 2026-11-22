defmodule PharmacyApp.Pharmacies.PlacesAdapter do
  @moduledoc """
  The provider boundary. All Google-specific translation — Googly struct
  pattern matching, `closes_at` conversion, walk-duration parsing, and
  place↔routing-summary pairing — lives here. Callers only see
  `PharmacyApp.Pharmacies.Pharmacy` structs and the documented
  result/error shapes.

  Each upstream call emits `[:pharmacy_app, :places, :request, :start |
  :stop | :exception]` telemetry. Metadata carries only the operation
  name and outcome status — never addresses, coordinates, or upstream
  messages. Each call also sets an explicit `receive_timeout` on the
  transport (default 5_000 ms, overridable via `:pharmacy_app,
  :places_receive_timeout`).
  """

  alias PharmacyApp.Pharmacies.Pharmacy

  @event [:pharmacy_app, :places, :request]

  @doc """
  Resolves a free-form address to coordinates (the vendored client has no
  separate geocode endpoint; Text Search with a one-place mask is used).

  Returns:

  * `{:ok, %{lat: float, lng: float, formatted_address: String.t}}` — top hit
  * `{:error, :address_not_found}` — Google returned nothing usable
  * `{:error, {:upstream, status, message}}` — Google rejected the request
  * `{:error, :upstream_unavailable}` — network/transport failure
  """
  def geocode(address, opts \\ []) do
    api_key = Application.fetch_env!(:pharmacy_app, :google_api_key)

    body = %Googly.Places.Model.GoogleMapsPlacesV1SearchTextRequest{
      text_query: address,
      page_size: 1,
      # Localizes formatted_address in the client's locale; nil is dropped
      # by the encoder, leaving Google's default (en-US).
      language_code: Keyword.get(opts, :language_code)
    }

    field_mask = "places.id,places.formattedAddress,places.location"

    instrument(:geocode, fn ->
      case Googly.Places.Places.search_text(
             body: body,
             key: api_key,
             req:
               ([headers: [{"x-goog-fieldmask", field_mask}],
                 receive_timeout: receive_timeout()] ++
                  extra_req_opts())
           ) do
        {:ok, %{places: [place | _]}} ->
          lat = place.location && place.location.latitude
          lng = place.location && place.location.longitude

          if is_nil(lat) or is_nil(lng) do
            {:error, :address_not_found}
          else
            {:ok,
             %{
               lat: lat,
               lng: lng,
               formatted_address: place.formatted_address || address
             }}
          end

        {:ok, _} ->
          {:error, :address_not_found}

        {:error, %Googly.Places.Error{} = error} ->
          {:error, {:upstream, error.status, error.message || "upstream error"}}

        {:error, _exception} ->
          {:error, :upstream_unavailable}
      end
    end)
  end

  @doc """
  Searches nearby pharmacies and translates the response in place:
  returns `{:ok, [%Pharmacy{}]}` without `distance_m` (origin-dependent,
  filled by the service), with routing summaries paired by position into
  the walk fields.

  Also returns the upstream error shapes:

  * `{:error, {:upstream, status, message}}` — Google rejected the request
  * `{:error, :upstream_unavailable}` — network/transport failure
  """
  def search_nearby(lat, lng, radius_m, opts \\ []) do
    api_key = Application.fetch_env!(:pharmacy_app, :google_api_key)

    body = %Googly.Places.Model.GoogleMapsPlacesV1SearchNearbyRequest{
      included_primary_types: ["pharmacy"],
      # Localizes display_name/formattedAddress and formats
      # currentOpeningHours.weekdayDescriptions in the client's locale.
      # nil is dropped by the encoder, leaving Google's default (en-US).
      language_code: Keyword.get(opts, :language_code),
      # RankPreference enum is DISTANCE | POPULARITY; DISTANCE = nearest-first
      rank_preference: "DISTANCE",
      max_result_count: 20,
      location_restriction:
        %Googly.Places.Model.GoogleMapsPlacesV1SearchNearbyRequestLocationRestriction{
          circle: %Googly.Places.Model.GoogleMapsPlacesV1Circle{
            center: %Googly.Places.Model.GoogleTypeLatLng{latitude: lat, longitude: lng},
            radius: radius_m
          }
        },
      # Walking time/distance from the user's point along real pedestrian
      # paths, returned as per-place routing summaries.
      routing_parameters: %Googly.Places.Model.GoogleMapsPlacesV1RoutingParameters{
        origin: %Googly.Places.Model.GoogleTypeLatLng{latitude: lat, longitude: lng},
        travel_mode: "WALK"
      }
    }

    field_mask =
      "places.id,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours,places.nationalPhoneNumber,places.utcOffsetMinutes,routingSummaries"

    instrument(:search_nearby, fn ->
      case Googly.Places.Places.search_nearby(
             body: body,
             key: api_key,
             req:
               ([headers: [{"x-goog-fieldmask", field_mask}],
                 receive_timeout: receive_timeout()] ++
                  extra_req_opts())
           ) do
        {:ok, response} ->
          {:ok,
           to_pharmacies(
             Map.get(response, :places) || [],
             Map.get(response, :routing_summaries) || []
           )}

        {:error, %Googly.Places.Error{} = error} ->
          {:error, {:upstream, error.status, error.message || "upstream error"}}

        {:error, _exception} ->
          {:error, :upstream_unavailable}
      end
    end)
  end

  @doc """
  Pairs Google places with their routing summaries by position and
  translates them to `%Pharmacy{}` structs (without `distance_m`).
  Public so translation is testable without a network call; the adapter
  uses it directly on each response.

  A place without coordinates is dropped together with its own summary;
  a missing, empty, or shorter summaries list leaves later places'
  walking fields nil instead of shifting a summary onto the wrong place.
  """
  def to_pharmacies(places, summaries) do
    {pharmacies, _} =
      Enum.map_reduce(places, summaries, fn
        place, [summary | rest] ->
          {translate(place, summary), rest}

        place, [] ->
          {translate(place, nil), []}
      end)

    # A place without coordinates is dropped together with its summary.
    Enum.reject(pharmacies, &is_nil/1)
  end

  @doc """
  Maps a `Googly.Places.Model.GoogleMapsPlacesV1Place` to the app-owned
  `%Pharmacy{}`, without `distance_m` (origin-dependent; the service
  fills it per request). Returns `nil` when the place carries no
  coordinates (Google omits `location` unless it was requested in the
  field mask); callers drop those results.

  `:open_now` and `:opening_hours` come from `currentOpeningHours`
  (next seven days incl. special hours); both are nil when Google
  returned no hours for the place. `:closes_at` is derived from
  `nextCloseTime` (only populated while the place is open) and formatted
  place-local as "HH:MM".
  """
  def from_place(place) do
    lat = place.location && place.location.latitude
    lng = place.location && place.location.longitude

    if is_nil(lat) or is_nil(lng) do
      nil
    else
      hours = place.current_opening_hours

      %Pharmacy{
        id: place.id,
        display_name: place.display_name && place.display_name.text,
        address: place.formatted_address,
        lat: lat,
        lng: lng,
        open_now: hours && hours.open_now,
        opening_hours: hours && hours.weekday_descriptions,
        closes_at: closes_at(hours, place.utc_offset_minutes),
        phone_number: place.national_phone_number
      }
    end
  end

  @doc """
  Attaches pedestrian-path distance/duration from the place's routing
  summary (same index as the place in the Google response). Uses the first
  leg — with a set origin, the summary has exactly one leg. No-op on nil
  summary; nil pharmacy passes through for pipeline use.
  """
  def put_walk(nil, _summary), do: nil

  def put_walk(%Pharmacy{} = pharmacy, nil), do: pharmacy

  def put_walk(%Pharmacy{} = pharmacy, summary) do
    case summary.legs do
      [%Googly.Places.Model.GoogleMapsPlacesV1RoutingSummaryLeg{} = leg | _] ->
        %Pharmacy{
          pharmacy
          | walk_distance_m: leg.distance_meters,
            walk_duration_s: parse_duration_s(leg.duration)
        }

      _ ->
        pharmacy
    end
  end

  defp translate(place, summary) do
    case from_place(place) do
      nil -> nil
      pharmacy -> put_walk(pharmacy, summary)
    end
  end

  # "Open until HH:MM" for the results page. nextCloseTime is only set
  # while the place is open, so a closed place (or 24/7, where the close
  # period is absent) yields nil. The vendored client decodes nextCloseTime
  # with DateTime.from_iso8601, which normalizes to UTC, so shift by the
  # place's utcOffsetMinutes to recover the place-local wall clock.
  defp closes_at(nil, _offset), do: nil

  defp closes_at(
         %Googly.Places.Model.GoogleMapsPlacesV1PlaceOpeningHours{
           open_now: true,
           next_close_time: %DateTime{} = dt
         },
         offset_minutes
       )
       when is_integer(dt.hour) and is_integer(dt.minute) and is_integer(offset_minutes) do
    local = DateTime.add(dt, offset_minutes * 60, :second)

    :io_lib.format("~2..0B:~2..0B", [local.hour, local.minute]) |> IO.iodata_to_binary()
  end

  defp closes_at(_, _), do: nil

  # Google durations are protobuf-style strings like "726s".
  defp parse_duration_s(duration) when is_binary(duration) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)s$/, duration) do
      [_, s] ->
        s
        |> then(&if String.contains?(&1, "."), do: &1, else: &1 <> ".0")
        |> String.to_float()
        |> round()

      _ ->
        nil
    end
  end

  defp parse_duration_s(_), do: nil

  defp receive_timeout do
    Application.get_env(:pharmacy_app, :places_receive_timeout, 5_000)
  end

  # Test seam: extra Req request opts (e.g. a fake `:adapter`) injected via
  # `:pharmacy_app, :places_req_opts`. Empty in production, so requests go
  # out unchanged through the default Finch transport.
  defp extra_req_opts do
    Application.get_env(:pharmacy_app, :places_req_opts, [])
  end

  # Wraps an upstream call in the request telemetry events. Stop/exception
  # metadata stays low-cardinality: operation name, outcome status, and for
  # exceptions the raised kind/reason — no addresses, coordinates, or
  # upstream messages.
  defp instrument(operation, fun) do
    :telemetry.execute(@event ++ [:start], %{system_time: System.system_time(:millisecond)}, %{
      operation: operation
    })

    start_ms = System.monotonic_time(:millisecond)

    try do
      result = fun.()

      :telemetry.execute(@event ++ [:stop], %{duration_ms: elapsed_ms(start_ms)}, %{
        operation: operation,
        status: status_of(result)
      })

      result
    rescue
      e ->
        :telemetry.execute(@event ++ [:exception], %{duration_ms: elapsed_ms(start_ms)}, %{
          operation: operation,
          kind: :error,
          reason: e
        })

        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        :telemetry.execute(@event ++ [:exception], %{duration_ms: elapsed_ms(start_ms)}, %{
          operation: operation,
          kind: kind,
          reason: reason
        })

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp elapsed_ms(start_ms), do: System.monotonic_time(:millisecond) - start_ms

  # :ok covers both success and a provider that answered normally
  # (e.g. geocode found no address); :upstream is a rejected request;
  # :unavailable is a transport failure.
  defp status_of({:ok, _}), do: :ok
  defp status_of({:error, :address_not_found}), do: :ok
  defp status_of({:error, {:upstream, _, _}}), do: :upstream
  defp status_of(_other), do: :unavailable
end
