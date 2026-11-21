defmodule PharmacyAppWeb.PharmaciesController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:json]

  alias PharmacyApp.Pharmacies.Service

  @doc """
  Error rendering policy for upstream errors: any Google status that is
  clearly client-side (4xx) is mirrored as-is; anything else (5xx, nil,
  unexpected) renders 502.
  """
  def index(conn, params) do
    case route(conn, params) do
      {:ok, pharmacies} ->
        json(conn, Enum.map(pharmacies, &Map.from_struct/1))

      {:error, {:invalid_params, issues}} ->
        conn
        |> put_status(422)
        |> json(%{errors: issues})

      {:error, :address_not_found} ->
        conn
        |> put_status(404)
        |> json(%{errors: ["address not found"]})

      {:error, {:upstream, status, message}}
      when is_integer(status) and status >= 400 and status < 500 ->
        conn
        |> put_status(status)
        |> json(%{errors: [%{status: status, message: message}]})

      {:error, {:upstream, status, message}} ->
        conn
        |> put_status(502)
        |> json(%{errors: [%{status: status, message: message}]})

      {:error, :upstream_unavailable} ->
        conn
        |> put_status(502)
        |> json(%{errors: ["upstream unavailable"]})
    end
  end

  # `q` (free-form address) is used only when lat/lng are absent; explicit
  # coordinates always win.
  defp route(conn, params) do
    q = trim(params["q"])
    lat = parse_float(params["lat"])
    lng = parse_float(params["lng"])

    cond do
      is_binary(q) and lat == nil and lng == nil ->
        case Service.search_by_address(
               q,
               [radius_m: parse_number(params["radius_m"]), language_code: parse_language(conn)] ++
                 service_opts()
             ) do
          # Same JSON shape as the coordinate path: a plain pharmacy list.
          {:ok, %{pharmacies: pharmacies}} -> {:ok, pharmacies}
          other -> other
        end

      true ->
        Service.search(parse_params(params, conn), service_opts())
    end
  end

  defp trim(nil), do: nil

  defp trim(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Extra opts (e.g. injected fake clients) come from application config so
  # tests can stub the upstream without network access.
  defp service_opts, do: Application.get_env(:pharmacy_app, :service_opts, [])

  defp parse_params(params, conn) do
    %{
      lat: parse_float(params["lat"]),
      lng: parse_float(params["lng"]),
      radius_m: parse_number(params["radius_m"]),
      language_code: parse_language(conn)
    }
  end

  # First Accept-Language tag wins; `*` or malformed tags fall back to the
  # upstream default (nil). Quality parameters after `;` are ignored.
  defp parse_language(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        tag =
          header
          |> String.split(",", parts: 2)
          |> hd()
          |> String.split(";", parts: 2)
          |> hd()
          |> String.trim()

        if Regex.match?(~r/\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/, tag), do: tag, else: nil

      _ ->
        nil
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(value) do
    case Float.parse(to_string(value)) do
      {f, ""} -> f
      _ -> :error
    end
  end

  defp parse_number(nil), do: nil

  defp parse_number(value) do
    case Float.parse(to_string(value)) do
      {f, ""} -> f
      _ -> :error
    end
  end
end
