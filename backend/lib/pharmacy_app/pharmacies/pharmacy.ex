defmodule PharmacyApp.Pharmacies do
  @moduledoc """
  Pure domain for the pharmacy search feature. No I/O happens here.
  """

  defstruct [
    :id,
    :display_name,
    :address,
    :lat,
    :lng,
    :distance_m,
    :open_now,
    :opening_hours,
    :closes_at,
    :phone_number,
    :walk_distance_m,
    :walk_duration_s
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          display_name: String.t() | nil,
          address: String.t() | nil,
          lat: float() | nil,
          lng: float() | nil,
          distance_m: number(),
          open_now: boolean() | nil,
          opening_hours: [String.t()] | nil,
          # Place-local "HH:MM" the pharmacy closes at, from
          # currentOpeningHours.nextCloseTime; nil when closed, hours
          # unknown, or open-ended (e.g. 24/7).
          closes_at: String.t() | nil,
          # National-format phone number as returned by Google.
          phone_number: String.t() | nil,
          # Pedestrian path to the search origin, from Google routing
          # summaries; nil when no summary was returned.
          walk_distance_m: number() | nil,
          walk_duration_s: integer() | nil
        }

  @radius_max 50_000
  @radius_default 1_000

  @doc """
  Validates lat/lng bounds and clamps radius_m to 1..50_000.

  Returns `{:ok, %{lat: float, lng: float, radius_m: pos_integer}}` or
  `{:error, [issues]}` with human-readable issues.
  """
  def validate_params(params) when is_map(params) do
    issues =
      Enum.reject(
        [lat_issue(params[:lat]), lng_issue(params[:lng]), language_issue(params[:language_code])],
        &is_nil/1
      )

    case issues do
      [] ->
        {:ok,
         %{
           lat: params[:lat] * 1.0,
           lng: params[:lng] * 1.0,
           radius_m: clamp_radius(params[:radius_m]),
           language_code: params[:language_code]
         }}

      issues ->
        {:error, issues}
    end
  end

  def validate_params(_), do: {:error, ["invalid parameters"]}

  defp lat_issue(lat) when is_number(lat) and lat >= -90 and lat <= 90, do: nil
  defp lat_issue(nil), do: "lat is required"
  defp lat_issue(_), do: "lat must be a number between -90 and 90"

  defp lng_issue(lng) when is_number(lng) and lng >= -180 and lng <= 180, do: nil
  defp lng_issue(nil), do: "lng is required"
  defp lng_issue(_), do: "lng must be a number between -180 and 180"

  defp language_issue(nil), do: nil

  defp language_issue(code) when is_binary(code) do
    if Regex.match?(~r/\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/, code),
      do: nil,
      else: "language_code must be a BCP-47 language tag"
  end

  defp language_issue(_), do: "language_code must be a string"

  defp clamp_radius(r) when is_number(r) and r >= 1, do: r |> min(@radius_max) |> max(1) |> trunc()
  defp clamp_radius(_), do: @radius_default

  @doc """
  Maps a `Googly.Places.Model.GoogleMapsPlacesV1Place` to the app-owned
  `%Pharmacy{}`, computing the haversine distance in metres from
  `user_point = {lat, lng}` locally.

  Returns `nil` when the place carries no coordinates (Google omits
  `location` unless it was requested in the field mask); callers should
  drop those results.

  `:open_now` and `:opening_hours` come from `currentOpeningHours`
  (next seven days incl. special hours); both are nil when Google
  returned no hours for the place. `:closes_at` is derived from
  `nextCloseTime` (only populated while the place is open) and formatted
  place-local as "HH:MM".
  """
  def from_google(
        %Googly.Places.Model.GoogleMapsPlacesV1Place{} = place,
        {user_lat, user_lng}
      ) do
    lat = place.location && place.location.latitude
    lng = place.location && place.location.longitude

    if is_nil(lat) or is_nil(lng) do
      nil
    else
      hours = place.current_opening_hours

      %__MODULE__{
        id: place.id,
        display_name: place.display_name && place.display_name.text,
        address: place.formatted_address,
        lat: lat,
        lng: lng,
        distance_m: haversine_m(user_lat, user_lng, lat, lng),
        open_now: hours && hours.open_now,
        opening_hours: hours && hours.weekday_descriptions,
        closes_at: closes_at(hours, place.utc_offset_minutes),
        phone_number: place.national_phone_number
      }
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

  @doc """
  Attaches pedestrian-path distance/duration from the place's routing
  summary (same index as the place in the Google response). Uses the first
  leg — with a set origin, the summary has exactly one leg. No-op on nil
  summary; nil pharmacy passes through for pipeline use.
  """
  def put_walk(nil, _summary), do: nil

  def put_walk(%__MODULE__{} = pharmacy, nil), do: pharmacy

  def put_walk(%__MODULE__{} = pharmacy, summary) do
    case summary.legs do
      [%Googly.Places.Model.GoogleMapsPlacesV1RoutingSummaryLeg{} = leg | _] ->
        %__MODULE__{
          pharmacy
          | walk_distance_m: leg.distance_meters,
            walk_duration_s: parse_duration_s(leg.duration)
        }

      _ ->
        pharmacy
    end
  end

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

  @doc """
  Keeps only pharmacies within `radius_m` metres.
  """
  def filter(pharmacies, radius_m) when is_list(pharmacies) and is_number(radius_m) do
    Enum.filter(pharmacies, &(&1.distance_m <= radius_m))
  end

  @doc """
  Sorts open pharmacies first, then by distance ascending. `open_now` nil
  (unknown) ranks with closed ones, ordered by distance among themselves.
  """
  def sort(pharmacies) when is_list(pharmacies) do
    Enum.sort_by(pharmacies, fn
      %{open_now: true, distance_m: d} -> {false, d}
      %{distance_m: d} -> {true, d}
    end)
  end

  @doc """
  Great-circle distance in metres (haversine), Earth radius 6_371_008.8 m.
  """
  def haversine_m(lat1, lng1, lat2, lng2) do
    dlat = deg2rad(lat2 - lat1)
    dlng = deg2rad(lng2 - lng1)

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(deg2rad(lat1)) * :math.cos(deg2rad(lat2)) * :math.sin(dlng / 2) ** 2

    c = 2 * :math.asin(:math.sqrt(a))
    6_371_008.8 * c
  end

  defp deg2rad(deg), do: deg * :math.pi() / 180
end
