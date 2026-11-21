defmodule PharmacyApp.Pharmacies do
  @moduledoc """
  Pure domain for the pharmacy search feature: input validation, radius
  handling, filtering, and sorting. No I/O and no provider-specific
  translation happen here (the latter lives in `PlacesAdapter`).
  """

  @radius_max 50_000
  @radius_default 1_000

  @doc """
  Validates lat/lng bounds and clamps radius_m to 1..50_000.

  Returns `{:ok, %{lat: float, lng: float, radius_m: pos_integer,
  language_code: code}}` or `{:error, [issues]}` with human-readable
  issues.
  """
  def validate_params(params) when is_map(params) do
    issues =
      Enum.reject(
        [
          lat_issue(params[:lat]),
          lng_issue(params[:lng]),
          language_issue(params[:language_code])
        ],
        &is_nil/1
      )

    case issues do
      [] ->
        {:ok,
         %{
           lat: params[:lat] * 1.0,
           lng: params[:lng] * 1.0,
           radius_m: effective_radius(params[:radius_m]),
           language_code: params[:language_code]
         }}

      issues ->
        {:error, issues}
    end
  end

  def validate_params(_), do: {:error, ["invalid parameters"]}

  @doc """
  Validates the search options that are independent of the origin:
  clamps `radius_m` via `effective_radius/1` and checks `language_code`.
  Used by the address path to fail fast before spending a geocode;
  coordinates are validated separately once resolved.

  Returns `{:ok, %{radius_m: pos_integer, language_code: code}}` or
  `{:error, [issues]}`.
  """
  def validate_options(opts) when is_map(opts) do
    case language_issue(opts[:language_code]) do
      nil ->
        {:ok, %{radius_m: effective_radius(opts[:radius_m]), language_code: opts[:language_code]}}

      issue ->
        {:error, [issue]}
    end
  end

  def validate_options(_), do: {:error, ["invalid parameters"]}

  @doc """
  Clamps a requested radius to a positive integer in 1..50_000; a
  missing or malformed radius defaults to 1_000. The effective radius is
  what the provider request, distance filtering, and any displayed
  radius text should agree on.
  """
  def effective_radius(radius_m) when is_number(radius_m) and radius_m >= 1,
    do: radius_m |> min(@radius_max) |> max(1) |> trunc()

  def effective_radius(_), do: @radius_default

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
