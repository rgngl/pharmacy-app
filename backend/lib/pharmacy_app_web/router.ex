defmodule PharmacyAppWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug PharmacyAppWeb.RateLimit
  end

  pipeline :browser do
    plug :accepts, ["html"]
  end

  scope "/", PharmacyAppWeb do
    pipe_through :api

    get "/api/pharmacies", PharmaciesController, :index
  end

  scope "/", PharmacyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end
end
