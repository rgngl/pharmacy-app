defmodule PharmacyApp.Pharmacies.PlacesAdapter do
  @moduledoc """
  The only module that talks to `Googly.Places`. Translates the generated
  client's results into service-level outcomes.
  """

  @doc """
  Searches nearby pharmacies. Returns:

  * `{:ok, [%Googly.Places.Model.GoogleMapsPlacesV1Place{}]}`
  * `{:error, {:upstream, status, message}}` — Google rejected the request
  * `{:error, :upstream_unavailable}` — network/transport failure
  """
  def search_nearby(lat, lng, radius_m, _opts \\ []) do
    api_key = Application.fetch_env!(:pharmacy_app, :google_api_key)

    body = %Googly.Places.Model.GoogleMapsPlacesV1SearchNearbyRequest{
      included_primary_types: ["pharmacy"],
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
      "places.id,places.displayName,places.formattedAddress,places.currentOpeningHours"

    case Googly.Places.Places.search_nearby(
           body: body,
           key: api_key,
           req: [headers: [{"x-goog-fieldmask", field_mask}]]
         ) do
      {:ok, %{places: places}} -> {:ok, places || []}
      {:ok, _} -> {:ok, []}
      {:error, %Googly.Places.Error{} = error} ->
        {:error, {:upstream, error.status, error.message || "upstream error"}}
      {:error, _exception} ->
        {:error, :upstream_unavailable}
    end
  end
end
