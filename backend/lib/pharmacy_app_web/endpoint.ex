defmodule PharmacyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :pharmacy_app

  # No static assets, no session; error pages render via ErrorHTML.
  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug PharmacyAppWeb.Router
end
