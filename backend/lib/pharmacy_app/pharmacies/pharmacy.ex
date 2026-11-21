defmodule PharmacyApp.Pharmacies.Pharmacy do
  @moduledoc """
  App-owned result shape for the pharmacy search feature. Filled by
  `PlacesAdapter` from provider data; `distance_m` is origin-dependent
  and therefore set by the service per request.
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
          # Straight-line distance in metres to the exact search origin;
          # nil until the service fills it per request.
          distance_m: number() | nil,
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
end
