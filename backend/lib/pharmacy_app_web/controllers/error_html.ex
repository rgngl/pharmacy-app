defmodule PharmacyAppWeb.ErrorHTML do
  @moduledoc """
  Minimal error pages. Phoenix renders these when a request raises before
  a controller (e.g. `Phoenix.Router.NoRouteError` for an unknown path such
  as `/favicon.ico`), which previously crashed again trying to render the
  default `ErrorView` that never existed in this app.
  """

  use Phoenix.Component

  embed_templates "error_html/*"
end
