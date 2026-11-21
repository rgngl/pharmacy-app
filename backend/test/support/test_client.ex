defmodule PharmacyApp.TestClient do
  @moduledoc """
  Injectable client for transport tests. The test stores a fun under
  `:pharmacy_app, :test_client_fn`; it receives (lat, lng, radius_m, opts)
  and returns the client contract's results.
  """

  def search_nearby(lat, lng, radius_m, opts \\ []) do
    fun = Application.fetch_env!(:pharmacy_app, :test_client_fn)
    fun.(lat, lng, radius_m, opts)
  end

  @doc """
  Injectable geocoder for address-search tests. The test stores a fun under
  `:pharmacy_app, :test_geocoder_fn`; it receives (address, opts) and
  returns the geocoder contract's results.
  """
  def geocode(address, opts \\ []) do
    fun = Application.fetch_env!(:pharmacy_app, :test_geocoder_fn)
    fun.(address, opts)
  end
end
