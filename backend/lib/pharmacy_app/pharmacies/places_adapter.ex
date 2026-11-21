defmodule PharmacyApp.Pharmacies.PlacesAdapter do
  @moduledoc """
  The only module that talks to `Googly.Places`. Translates the generated
  client's results into service-level outcomes.
  """

  @doc """
  Resolves a free-form address to coordinates with Text Search (the vendored
  Places client has no dedicated geocoding endpoint). Returns:

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

    case Googly.Places.Places.search_text(
           body: body,
           key: api_key,
           req: [headers: [{"x-goog-fieldmask", field_mask}]]
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
  end

  @doc """
  Searches nearby pharmacies. Returns:

  * `{:ok, [%Googly.Places.Model.GoogleMapsPlacesV1Place{}]}`
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
        }
    }

    field_mask =
      "places.id,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours"

    case Googly.Places.Places.search_nearby(
           body: body,
           key: api_key,
           req: [headers: [{"x-goog-fieldmask", field_mask}]]
         ) do
      {:ok, %{places: places}} ->
        {:ok, places || []}

      {:error, %Googly.Places.Error{} = error} ->
        {:error, {:upstream, error.status, error.message || "upstream error"}}

      {:error, _exception} ->
        {:error, :upstream_unavailable}
    end
  end
end
