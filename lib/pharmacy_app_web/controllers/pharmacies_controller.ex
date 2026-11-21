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
    case Service.search(parse_params(params), service_opts()) do
      {:ok, pharmacies} ->
        json(conn, Enum.map(pharmacies, &Map.from_struct/1))

      {:error, {:invalid_params, issues}} ->
        conn
        |> put_status(422)
        |> json(%{errors: issues})

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

  # Extra opts (e.g. injected fake clients) come from application config so
  # tests can stub the upstream without network access.
  defp service_opts, do: Application.get_env(:pharmacy_app, :service_opts, [])

  defp parse_params(params) do
    %{
      lat: parse_float(params["lat"]),
      lng: parse_float(params["lng"]),
      radius_m: parse_number(params["radius_m"])
    }
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
