defmodule PharmacyAppWeb.ErrorJSON do
  @moduledoc """
  JSON error rendering for requests that negotiate JSON but raise before a
  controller (e.g. `Phoenix.Router.NoRouteError` for an unknown /api path).
  """

  def render("404.json", _assigns), do: %{errors: ["not found"]}
  def render("500.json", _assigns), do: %{errors: ["internal server error"]}

  def render(template, _assigns) when is_binary(template) do
    %{errors: ["internal server error"]}
  end
end
