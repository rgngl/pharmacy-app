defmodule PharmacyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :pharmacy_app

  # JSON API only: no static assets, no session, no HTML rendering.
  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug PharmacyAppWeb.Router
end
