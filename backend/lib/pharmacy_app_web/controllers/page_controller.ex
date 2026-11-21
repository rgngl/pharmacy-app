defmodule PharmacyAppWeb.PageController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:html]

  alias PharmacyApp.Pharmacies.Service

  # Minimal page: no shared layout module, render the template standalone.
  plug(:put_layout, false)

  @doc """
  Server-rendered search page. Same param mapping and error mapping as
  `PharmaciesController.index/2`, but renders HTML:

  - no params at all → form only (`:searched` false)
  - `q` (free-form address, when lat/lng are absent) → geocode then search
  - invalid params → 200 with inline per-field errors
  - upstream errors → mirrored 4xx / 502 with a banner
  """
  def home(conn, params) do
    raw = %{
      "lat" => params["lat"],
      "lng" => params["lng"],
      "radius_m" => params["radius_m"],
      "q" => params["q"]
    }

    cond do
      Enum.all?(Map.values(raw), &is_nil/1) ->
        render(conn,
          no_params: true,
          searched: false,
          submitted: raw,
          errors: [],
          banner: nil,
          resolved: nil,
          pharmacies: []
        )

      # Free-form address wins only when no explicit coordinates were sent.
      is_binary(trim(raw["q"])) and is_nil(parse_float(raw["lat"])) and
          is_nil(parse_float(raw["lng"])) ->
        render_outcome(
          conn,
          raw,
          Service.search_by_address(
            String.trim(raw["q"]),
            [radius_m: parse_number(raw["radius_m"]), language_code: parse_language(conn)] ++
              service_opts()
          )
        )

      true ->
        render_outcome(conn, raw, Service.search(parse_params(params, conn), service_opts()))
    end
  end

  # Uniform render for both flows: the address flow's success carries
  # `%{pharmacies: …, formatted_address: …}`, the coordinate flow's a plain
  # pharmacy list. Error shapes are identical.
  defp render_outcome(conn, raw, result) do
    case result do
      {:ok, %{pharmacies: pharmacies, formatted_address: formatted_address}} ->
        render(conn,
          no_params: false,
          searched: true,
          submitted: raw,
          errors: [],
          banner: nil,
          resolved: formatted_address,
          pharmacies: pharmacies
        )

      {:ok, pharmacies} ->
        render(conn,
          no_params: false,
          searched: true,
          submitted: raw,
          errors: [],
          banner: nil,
          resolved: nil,
          pharmacies: pharmacies
        )

      {:error, :address_not_found} ->
        render(conn,
          no_params: false,
          searched: false,
          submitted: raw,
          errors: [],
          banner:
            "Couldn't find an address matching \u201C#{String.trim(raw["q"])}\u201D. Try a more specific address.",
          resolved: nil,
          pharmacies: []
        )

      {:error, {:invalid_params, issues}} ->
        render(conn,
          no_params: false,
          searched: false,
          submitted: raw,
          errors: issues,
          banner: nil,
          resolved: nil,
          pharmacies: []
        )

      {:error, {:upstream, status, message}}
      when is_integer(status) and status >= 400 and status < 500 ->
        conn
        |> put_status(status)
        |> render_upstream_error(raw, status, message)

      {:error, {:upstream, status, message}} ->
        conn
        |> put_status(502)
        |> render_upstream_error(raw, status, message)

      {:error, :upstream_unavailable} ->
        conn
        |> put_status(502)
        |> render(
          no_params: false,
          searched: false,
          submitted: raw,
          errors: [],
          banner: "Upstream unavailable — please try again later.",
          resolved: nil,
          pharmacies: []
        )
    end
  end

  defp render_upstream_error(conn, raw, status, message) do
    render(conn,
      no_params: false,
      searched: false,
      submitted: raw,
      errors: [],
      banner: "Upstream error (#{status}): #{message}",
      resolved: nil,
      pharmacies: []
    )
  end

  # Same opts plumbing as PharmaciesController: injected fake clients from
  # application config so tests can stub the upstream.
  defp service_opts, do: Application.get_env(:pharmacy_app, :service_opts, [])

  defp trim(nil), do: nil

  defp trim(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp parse_params(params, conn) do
    %{
      lat: parse_float(params["lat"]),
      lng: parse_float(params["lng"]),
      radius_m: parse_number(params["radius_m"]),
      language_code: parse_language(conn)
    }
  end

  # Mirrors PharmaciesController.parse_language/1.
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
