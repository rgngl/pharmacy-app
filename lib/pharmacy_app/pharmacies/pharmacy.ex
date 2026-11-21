defmodule PharmacyApp.Pharmacies do
  @moduledoc """
  Pure domain for the pharmacy search feature. No I/O happens here.
  """

  defstruct [:id, :display_name, :address, :lat, :lng, :distance_m, :open_now, :opening_hours]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          display_name: String.t() | nil,
          address: String.t() | nil,
          lat: float() | nil,
          lng: float() | nil,
          distance_m: number(),
          open_now: boolean() | nil,
          opening_hours: [String.t()] | nil
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
      Enum.reject([lat_issue(params[:lat]), lng_issue(params[:lng])], &is_nil/1)

    case issues do
      [] ->
        {:ok,
         %{
           lat: params[:lat] * 1.0,
           lng: params[:lng] * 1.0,
           radius_m: clamp_radius(params[:radius_m])
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

  defp clamp_radius(r) when is_number(r) and r >= 1, do: r |> min(@radius_max) |> max(1) |> trunc()
  defp clamp_radius(_), do: @radius_default

  @doc """
  Maps a `Googly.Places.Model.GoogleMapsPlacesV1Place` to the app-owned
  `%Pharmacy{}`, computing the haversine distance in metres from
  `user_point = {lat, lng}` locally.

  `:open_now` and `:opening_hours` come from `currentOpeningHours`
  (next seven days incl. special hours); both are nil when Google
  returned no hours for the place.
  """
  def from_google(
        %Googly.Places.Model.GoogleMapsPlacesV1Place{} = place,
        {user_lat, user_lng}
      ) do
    lat = place.location && place.location.latitude
    lng = place.location && place.location.longitude
    hours = place.current_opening_hours

    %__MODULE__{
      id: place.id,
      display_name: place.display_name && place.display_name.text,
      address: place.formatted_address,
      lat: lat,
      lng: lng,
      distance_m: haversine_m(user_lat, user_lng, lat, lng),
      open_now: hours && hours.open_now,
      opening_hours: hours && hours.weekday_descriptions
    }
  end

  @doc """
  Keeps only pharmacies within `radius_m` metres.
  """
  def filter(pharmacies, radius_m) when is_list(pharmacies) and is_number(radius_m) do
    Enum.filter(pharmacies, &(&1.distance_m <= radius_m))
  end

  @doc """
  Sorts pharmacies by distance, ascending.
  """
  def sort(pharmacies) when is_list(pharmacies) do
    Enum.sort_by(pharmacies, & &1.distance_m, :asc)
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
