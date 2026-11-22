defmodule PharmacyApp.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      PharmacyApp.Pharmacies.Cache,
      # Rate-limit table must exist before the Endpoint serves requests.
      PharmacyAppWeb.RateLimit.Sweeper,
      PharmacyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PharmacyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
