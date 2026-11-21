defmodule PharmacyAppWeb.Params do
  @moduledoc """
  The single web-input parser for both search entry points (the HTML page
  served by `PharmacyAppWeb.PageController` and the JSON API served by
  `PharmacyAppWeb.PharmaciesController`).

  Both controllers call `parse/2` and dispatch on the returned struct, so
  origin precedence, radius policy, and language selection are identical
  across HTML and JSON. Type checks run before trimming/parsing, so
  structured or non-scalar query values yield controlled `:issues` instead
  of raising in `to_string/1`.
  """

  alias PharmacyApp.Pharmacies

  defstruct [:origin, :lat, :lng, :q, :radius_m, :language_code, issues: []]

  @type t :: %__MODULE__{
          # `:none` — no search input at all (form-only page);
          # `:coords` — explicit lat/lng won (they always beat `q`);
          # `:address` — `q` won because both coordinates were absent.
          origin: :none | :coords | :address,
          lat: float() | nil,
          lng: float() | nil,
          q: String.t() | nil,
          # Always present: the effective (clamped) radius. Malformed,
          # non-scalar, or absent values fall back to the domain default —
          # a deliberate decision; there is no validation error for radius.
          radius_m: pos_integer(),
          language_code: String.t() | nil,
          # Web-level input errors: non-scalar values and scalars that do
          # not parse. Empty when the parse is usable.
          issues: [String.t()]
        }

  @doc """
  Parses the request's search input into the effective search.

  * Explicit coordinates win over `q`; `q` becomes the origin only when
    both coordinates are absent (nil or blank).
  * The radius is always populated via `Pharmacies.effective_radius/1`.
  * `language_code` comes from the first valid Accept-Language tag; `*`
    and malformed tags fall back to the upstream default (nil).
  """
  @spec parse(term(), Plug.Conn.t()) :: t()
  def parse(params, conn) when is_map(params) do
    %__MODULE__{
      origin: :none,
      radius_m: effective_radius(params["radius_m"]),
      language_code: language_code(conn)
    }
    |> put_origin(params["lat"], params["lng"], params["q"])
  end

  def parse(_params, _conn), do: %__MODULE__{origin: :none, issues: ["invalid parameters"]}

  @doc """
  Domain `Service.search/2` params for a coordinate-origin parse. For a
  `:none` origin the coordinates are nil, so the domain answers with its
  documented "missing coordinates" 422 before any upstream call.
  """
  def search_params(%__MODULE__{
        origin: origin,
        lat: lat,
        lng: lng,
        radius_m: radius_m,
        language_code: language_code
      })
      when origin in [:coords, :none] do
    %{lat: lat, lng: lng, radius_m: radius_m, language_code: language_code}
  end

  # -- Origin precedence -----------------------------------------------------

  # Precedence: explicit coordinates win over `q`. An invalid coordinate is
  # a controlled input error — the parser never falls back to `q` when
  # coordinates were sent but unparseable, matching the controllers' old
  # route semantics.
  defp put_origin(parsed, lat_raw, lng_raw, q_raw) do
    issues = input_issues(lat: lat_raw, lng: lng_raw, q: q_raw)

    cond do
      issues != [] ->
        %{parsed | origin: :coords, issues: issues}

      absent?(lat_raw) and absent?(lng_raw) and absent?(q_raw) ->
        parsed

      absent?(lat_raw) and absent?(lng_raw) ->
        %{parsed | origin: :address, q: String.trim(q_raw)}

      true ->
        %{parsed | origin: :coords, lat: parse_float(lat_raw), lng: parse_float(lng_raw)}
    end
  end

  # Input classification: absent means nil or blank; anything else must be
  # a scalar (string or number) or it is reported as an issue before any
  # to_string/1 can raise on a structured value.
  defp absent?(nil), do: true
  defp absent?(raw) when is_binary(raw), do: String.trim(raw) == ""
  defp absent?(_), do: false

  defp input_issues(inputs) do
    for {name, raw} <- inputs, issue = field_issue(name, raw) do
      issue
    end
  end

  # Wording matches the domain's validation text for lat/lng so HTML and
  # JSON report the same issues regardless of which layer rejects the value.
  defp field_issue(:q, raw) when is_binary(raw), do: nil
  defp field_issue(:q, nil), do: nil
  defp field_issue(:q, _), do: "q must be a string"

  defp field_issue(name, raw) when name in [:lat, :lng] do
    if valid_coordinate?(raw), do: nil, else: "#{name} must be a number between -90 and 90"
  end

  defp valid_coordinate?(nil), do: true
  defp valid_coordinate?(raw) when is_number(raw), do: true

  defp valid_coordinate?(raw) when is_binary(raw) do
    case raw |> String.trim() |> Float.parse() do
      {_f, ""} -> true
      _ -> false
    end
  end

  defp valid_coordinate?(_), do: false

  # Precondition: field_issue/2 returned nil for these values, so present
  # scalars always parse. Absent values become nil for the domain to
  # report as "required".
  defp parse_float(nil), do: nil
  defp parse_float(raw) when is_number(raw), do: raw * 1.0

  defp parse_float(raw) when is_binary(raw) do
    {f, ""} = raw |> String.trim() |> Float.parse()
    f
  end

  # -- Radius ------------------------------------------------------------------

  # Malformed, non-scalar, or absent radii fall back to the domain default;
  # present numbers are clamped. Deliberate: no validation error for radius.
  defp effective_radius(nil), do: Pharmacies.effective_radius(nil)

  defp effective_radius(raw) when is_binary(raw) do
    case raw |> String.trim() |> Float.parse() do
      {r, ""} -> Pharmacies.effective_radius(r)
      _ -> Pharmacies.effective_radius(nil)
    end
  end

  defp effective_radius(raw) when is_number(raw), do: Pharmacies.effective_radius(raw)
  defp effective_radius(_), do: Pharmacies.effective_radius(nil)

  # -- Language ----------------------------------------------------------------

  # First Accept-Language tag wins; `*` or malformed tags fall back to the
  # upstream default (nil). Quality parameters after `;` are ignored.
  defp language_code(conn) do
    case Plug.Conn.get_req_header(conn, "accept-language") do
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
end
