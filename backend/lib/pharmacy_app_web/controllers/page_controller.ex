defmodule PharmacyAppWeb.PageController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:html]

  alias PharmacyApp.Pharmacies.Service
  alias PharmacyAppWeb.Params

  # Minimal page: no shared layout module, render the template standalone.
  plug(:put_layout, false)

  @doc """
  Server-rendered search page. Same param mapping and error mapping as
  `PharmaciesController.index/2`, but renders HTML:

  - no search input at all → form only (origin `:none`, `:searched` false)
  - `q` (free-form address, when lat/lng are absent) → geocode then search
  - invalid params → 200 with inline per-field errors
  - upstream errors → mirrored 4xx / 502 with a banner

  The template receives the *effective* search as `@search` (a
  `PharmacyAppWeb.Params` struct: origin mode, clamped radius) and the raw
  submitted values as `@submitted` only so the form can redisplay them.
  """
  def home(conn, params) do
    parsed = Params.parse(params, conn)
    submitted = raw_input(params)

    cond do
      parsed.issues != [] ->
        render(conn,
          no_params: false,
          searched: false,
          submitted: submitted,
          search: parsed,
          errors: parsed.issues,
          banner: nil,
          resolved: nil,
          pharmacies: []
        )

      parsed.origin == :none ->
        render(conn,
          no_params: true,
          searched: false,
          submitted: submitted,
          search: parsed,
          errors: [],
          banner: nil,
          resolved: nil,
          pharmacies: []
        )

      parsed.origin == :address ->
        render_outcome(
          conn,
          submitted,
          parsed,
          Service.search_by_address(
            parsed.q,
            [radius_m: parsed.radius_m, language_code: parsed.language_code] ++ service_opts()
          )
        )

      true ->
        render_outcome(
          conn,
          submitted,
          parsed,
          Service.search(Params.search_params(parsed), service_opts())
        )
    end
  end

  # Uniform render for both flows: the address flow's success carries
  # `%{pharmacies: …, formatted_address: …}`, the coordinate flow's a plain
  # pharmacy list. Error shapes are identical.
  defp render_outcome(conn, submitted, search, result) do
    case result do
      {:ok, %{pharmacies: pharmacies, formatted_address: formatted_address}} ->
        render(conn,
          no_params: false,
          searched: true,
          submitted: submitted,
          search: search,
          errors: [],
          banner: nil,
          resolved: formatted_address,
          pharmacies: pharmacies
        )

      {:ok, pharmacies} ->
        render(conn,
          no_params: false,
          searched: true,
          submitted: submitted,
          search: search,
          errors: [],
          banner: nil,
          resolved: nil,
          pharmacies: pharmacies
        )

      {:error, :address_not_found} ->
        render(conn,
          no_params: false,
          searched: false,
          submitted: submitted,
          search: search,
          errors: [],
          banner:
            "Couldn't find an address matching \u201C#{search.q}\u201D. Try a more specific address.",
          resolved: nil,
          pharmacies: []
        )

      {:error, {:invalid_params, issues}} ->
        render(conn,
          no_params: false,
          searched: false,
          submitted: submitted,
          search: search,
          errors: issues,
          banner: nil,
          resolved: nil,
          pharmacies: []
        )

      {:error, {:upstream, status, message}}
      when is_integer(status) and status >= 400 and status < 500 ->
        conn
        |> put_status(status)
        |> render_upstream_error(submitted, search, status, message)

      {:error, {:upstream, status, message}} ->
        conn
        |> put_status(502)
        |> render_upstream_error(submitted, search, status, message)

      {:error, :upstream_unavailable} ->
        conn
        |> put_status(502)
        |> render(
          no_params: false,
          searched: false,
          submitted: submitted,
          search: search,
          errors: [],
          banner: "Upstream unavailable — please try again later.",
          resolved: nil,
          pharmacies: []
        )
    end
  end

  defp render_upstream_error(conn, submitted, search, status, message) do
    render(conn,
      no_params: false,
      searched: false,
      submitted: submitted,
      search: search,
      errors: [],
      banner: "Upstream error (#{status}): #{message}",
      resolved: nil,
      pharmacies: []
    )
  end

  # Same opts plumbing as PharmaciesController: injected fake clients from
  # application config so tests can stub the upstream.
  defp service_opts, do: Application.get_env(:pharmacy_app, :service_opts, [])

  # Raw submitted values, only so the form can redisplay what the user sent.
  # All parsing, precedence, and clamping live in PharmacyAppWeb.Params;
  # non-binary values are dropped here because they are never valid input
  # and must not reach the template's attribute rendering.
  defp raw_input(params) do
    %{
      "lat" => binary_or_nil(params["lat"]),
      "lng" => binary_or_nil(params["lng"]),
      "radius_m" => binary_or_nil(params["radius_m"]),
      "q" => binary_or_nil(params["q"])
    }
  end

  defp binary_or_nil(value) when is_binary(value), do: value
  defp binary_or_nil(_), do: nil
end
