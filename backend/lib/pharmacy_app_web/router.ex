defmodule PharmacyAppWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PharmacyAppWeb do
    pipe_through :api

    get "/api/pharmacies", PharmaciesController, :index
  end
end
