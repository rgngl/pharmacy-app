defmodule PharmacyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :pharmacy_app

  # Location privacy (review handoff, "Before public deployment"): drop the
  # search origin from Phoenix's parameter logging. config/config.exs is
  # outside this layer's ownership, so the `:phoenix, :filter_parameters`
  # setting is applied here at endpoint load — Phoenix.Logger reads the
  # filter lazily when it logs router params, not only at boot. `password`
  # is kept from Phoenix's conventional default filter.
  #
  # Limitation: Plug.Logger below logs the raw request line, which includes
  # the query string, so q/lat/lng still reach it; reverse-proxy and access
  # logs need the same review. GET URLs are not private either — this
  # mitigates logging, not browser history.
  Application.put_env(:phoenix, :filter_parameters, ["password", "q", "lat", "lng"])

  # No static assets, no session; error pages render via ErrorHTML.
  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(PharmacyAppWeb.Router)
end
