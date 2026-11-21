defmodule PharmacyAppWeb.PageHTML do
  @moduledoc """
  Embedded HEEx templates for the pharmacy search page.
  """

  use Phoenix.Component
  import PharmacyAppWeb.Components

  alias PharmacyAppWeb.Params

  embed_templates("page_html/*")

  @doc """
  Stable query params for the radius chips, built from the *effective*
  search mode: coordinate searches keep lat/lng (q is dropped), address
  searches keep q (coordinates are dropped). nil when there is no origin
  to link to.
  """
  def chip_query(%Params{origin: :address, q: q}) when is_binary(q) and q != "" do
    %{"q" => q}
  end

  def chip_query(%Params{origin: :coords, lat: lat, lng: lng}) when lat != nil and lng != nil do
    %{"lat" => lat, "lng" => lng}
  end

  def chip_query(_), do: nil

  @doc """
  Radius shown in result text: the effective (clamped) value from the
  parser. Raw input is never re-parsed here.
  """
  def radius_text(%Params{radius_m: m}) when is_integer(m), do: "#{m} m"
end
