defmodule PharmacyAppWeb.PharmaciesController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:json]

  alias PharmacyApp.Pharmacies.Pharmacy
  alias PharmacyApp.Pharmacies.Service
  alias PharmacyAppWeb.Params

  @doc """
  Error rendering policy for upstream errors: any Google status that is
  clearly client-side (4xx) is mirrored as-is; anything else (5xx, nil,
  unexpected) renders 502.
  """
  def index(conn, params) do
    case Params.parse(params, conn) do
      %Params{issues: []} = parsed ->
        respond(conn, route(conn, parsed))

      %Params{issues: issues} ->
        conn
        |> put_status(422)
        |> json(%{errors: issues})
    end
  end

  # `q` (free-form address) is used only when lat/lng are absent; explicit
  # coordinates always win. Precedence lives in PharmacyAppWeb.Params; for a
  # `:none` origin, search_params/1 sends nil coordinates so the domain
  # answers the documented missing-coordinates 422 before any upstream call.
  defp route(_conn, %Params{origin: :address} = parsed) do
    case Service.search_by_address(
           parsed.q,
           [radius_m: parsed.radius_m, language_code: parsed.language_code] ++ service_opts()
         ) do
      # Same JSON shape as the coordinate path: a plain pharmacy list.
      {:ok, %{pharmacies: pharmacies}} -> {:ok, pharmacies}
      other -> other
    end
  end

  defp route(_conn, %Params{origin: origin} = parsed) when origin in [:coords, :none] do
    Service.search(Params.search_params(parsed), service_opts())
  end

  defp respond(conn, {:ok, pharmacies}) do
    json(conn, Enum.map(pharmacies, &serialize/1))
  end

  defp respond(conn, {:error, {:invalid_params, issues}}) do
    conn
    |> put_status(422)
    |> json(%{errors: issues})
  end

  defp respond(conn, {:error, :address_not_found}) do
    conn
    |> put_status(404)
    |> json(%{errors: ["address not found"]})
  end

  defp respond(conn, {:error, {:upstream, status, message}})
       when is_integer(status) and status >= 400 and status < 500 do
    conn
    |> put_status(status)
    |> json(%{errors: [%{status: status, message: message}]})
  end

  defp respond(conn, {:error, {:upstream, status, message}}) do
    conn
    |> put_status(502)
    |> json(%{errors: [%{status: status, message: message}]})
  end

  defp respond(conn, {:error, :upstream_unavailable}) do
    conn
    |> put_status(502)
    |> json(%{errors: ["upstream unavailable"]})
  end

  # Explicit serializer: the API contract lists exactly these fields with
  # this nil handling (identical to the previous blanket struct-to-map
  # output, so no client-visible field disappears), but new internal fields
  # can no longer leak into the response by default.
  defp serialize(%Pharmacy{} = pharmacy) do
    %{
      id: pharmacy.id,
      display_name: pharmacy.display_name,
      address: pharmacy.address,
      lat: pharmacy.lat,
      lng: pharmacy.lng,
      distance_m: pharmacy.distance_m,
      open_now: pharmacy.open_now,
      opening_hours: pharmacy.opening_hours,
      closes_at: pharmacy.closes_at,
      phone_number: pharmacy.phone_number,
      walk_distance_m: pharmacy.walk_distance_m,
      walk_duration_s: pharmacy.walk_duration_s
    }
  end

  # Extra opts (e.g. injected fake clients) come from application config so
  # tests can stub the upstream without network access.
  defp service_opts, do: Application.get_env(:pharmacy_app, :service_opts, [])
end
