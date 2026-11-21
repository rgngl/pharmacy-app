defmodule PharmacyAppWeb.Components do
  @moduledoc """
  Reusable HEEx function components shared across pages.

  Styles ship as a single `<.stylesheet />` component (the app has no
  static-asset pipeline); pages embedding components render it once.
  """

  use Phoenix.Component

  alias PharmacyApp.Pharmacies

  # -- Stylesheet -----------------------------------------------------------

  @doc """
  The shared stylesheet for pages using these components. Render once per
  page, ideally in `<head>`.
  """
  def stylesheet(assigns) do
    ~H"""
    <style>
      :root {
        color-scheme: light;
        --green: #2e7d4f;
        --green-dark: #266a42;
        --green-soft: #e7f2eb;
        --red-soft: #fdeaea;
        --red-text: #b3261e;
        --bg: #f5f6f8;
        --card: #ffffff;
        --border: #e4e7ea;
        --text: #1a1d21;
        --muted: #6b7280;
      }
      * { box-sizing: border-box; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
          "Helvetica Neue", Arial, sans-serif;
        margin: 0;
        background: var(--bg);
        color: var(--text);
        line-height: 1.5;
      }
      .page {
        max-width: 880px;
        margin: 0 auto;
        padding: 0 1rem 3rem;
      }
      .page-head {
        background: var(--card);
        border-bottom: 1px solid var(--border);
        margin: 0 -1rem;
        padding: 1.75rem 1rem 1.5rem;
      }
      .page-head-inner { max-width: 848px; margin: 0 auto; }
      .head-row { display: flex; align-items: center; gap: 0.9rem; margin-bottom: 1.25rem; }
      .head-icon {
        flex: 0 0 44px;
        width: 44px; height: 44px;
        display: flex; align-items: center; justify-content: center;
        background: var(--green);
        color: #fff;
        border-radius: 12px;
        font-size: 1.6rem; font-weight: 600;
      }
      h1 { font-size: 1.55rem; margin: 0; letter-spacing: -0.01em; }
      .sub { margin: 0.1rem 0 0; color: var(--muted); font-size: 0.95rem; }

      .search-row { display: flex; gap: 0.6rem; flex-wrap: wrap; }
      .search-box {
        flex: 1 1 20rem;
        display: flex; align-items: center; gap: 0.6rem;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 12px;
        padding: 0 0.9rem;
        min-height: 48px;
      }
      .search-box:focus-within { border-color: var(--green); }
      .search-box svg { flex: 0 0 auto; color: var(--muted); }
      .search-box input {
        flex: 1 1 auto;
        border: none; outline: none;
        background: transparent;
        font: inherit;
        color: var(--text);
        min-width: 0;
        padding: 0.65rem 0;
      }

      button, .btn {
        display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem;
        min-height: 48px;
        padding: 0 1.25rem;
        border-radius: 12px;
        font: inherit; font-weight: 600;
        cursor: pointer;
        text-decoration: none;
        white-space: nowrap;
      }
      .btn-primary {
        background: var(--green); color: #fff;
        border: 1px solid var(--green);
      }
      .btn-primary:hover { background: var(--green-dark); }
      .btn-outline {
        background: var(--card); color: var(--text);
        border: 1px solid var(--border);
      }
      .btn-outline:hover { border-color: var(--muted); }

      .filter-row {
        display: flex; align-items: center; gap: 0.5rem;
        flex-wrap: wrap;
        margin-top: 1.1rem;
        font-size: 0.9rem;
      }
      .radius-label {
        text-transform: uppercase; letter-spacing: 0.04em;
        color: var(--muted); font-weight: 600; font-size: 0.78rem;
      }
      .chip {
        padding: 0.3rem 0.85rem;
        border: 1px solid var(--border);
        border-radius: 999px;
        background: var(--card);
        color: var(--text);
        text-decoration: none;
        font-weight: 500;
      }
      .chip:hover { border-color: var(--green); color: var(--green); }
      .chip.active {
        background: var(--green); border-color: var(--green); color: #fff;
      }
      .count { margin-left: auto; color: var(--muted); }
      .count strong { color: var(--text); }

      main { padding-top: 1.5rem; }

      .status {
        display: flex; align-items: center; gap: 0.6rem;
        padding: 0.9rem 1rem;
        border: 1px solid var(--border);
        border-radius: 12px;
        background: var(--card);
        color: var(--muted);
        margin-bottom: 1rem;
      }
      .status.error {
        background: var(--red-soft);
        color: var(--red-text);
        border-color: #e5a89f;
        display: block;
      }
      .spinner {
        width: 1rem; height: 1rem; flex: 0 0 1rem;
        border: 2px solid #bbb; border-top-color: var(--green);
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
      }
      @keyframes spin { to { transform: rotate(360deg); } }
      .status.error .retry { margin-top: 0.5rem; }
      .retry {
        min-height: 36px; padding: 0 0.9rem;
        background: var(--red-text); color: #fff; border: none;
      }

      .banner, .errors {
        background: var(--red-soft);
        color: var(--red-text);
        border: 1px solid #e5a89f;
        padding: 0.75rem 1rem;
        border-radius: 12px;
        margin: 0 0 1rem;
      }
      .errors ul { margin: 0; padding-left: 1.25rem; }

      .card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 16px;
        padding: 1.25rem 1.4rem;
        margin-bottom: 1rem;
      }
      .card-top { display: flex; align-items: baseline; gap: 0.75rem; flex-wrap: wrap; }
      .card-name { font-size: 1.2rem; font-weight: 700; margin: 0; }
      .distance-pill {
        margin-left: auto;
        display: inline-flex; align-items: center; gap: 0.4rem;
        border: 1px solid var(--border);
        border-radius: 999px;
        padding: 0.25rem 0.85rem;
        font-size: 0.85rem;
        color: var(--muted);
      }
      .distance-pill strong { color: var(--text); }
      .card-address {
        display: flex; align-items: center; gap: 0.45rem;
        color: var(--muted);
        margin-top: 0.5rem;
      }
      .card-address svg { flex: 0 0 auto; }
      .card-divider { border: none; border-top: 1px solid var(--border); margin: 1rem 0; }
      .hours-row { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
      .open-pill {
        display: inline-flex; align-items: center; gap: 0.45rem;
        background: var(--green-soft); color: var(--green);
        font-weight: 600; font-size: 0.88rem;
        border-radius: 999px;
        padding: 0.3rem 0.9rem;
      }
      .open-pill::before {
        content: "";
        width: 7px; height: 7px; border-radius: 50%;
        background: var(--green);
      }
      .open-pill.closed { background: var(--red-soft); color: var(--red-text); }
      .open-pill.closed::before { background: var(--red-text); }
      .open-pill.unknown { background: #eef0f2; color: var(--muted); }
      .open-pill.unknown::before { background: var(--muted); }

      .hours-details { margin-left: auto; color: var(--muted); font-size: 0.9rem; }
      .hours-details summary {
        cursor: pointer; list-style: none;
        display: inline-flex; align-items: center; gap: 0.35rem;
        font-weight: 500;
      }
      .hours-details summary::-webkit-details-marker { display: none; }
      .hours-details summary svg { transition: transform 0.15s ease; }
      .hours-details[open] summary svg { transform: rotate(180deg); }
      .hours-list {
        margin: 0.75rem 0 0; padding: 0.75rem 1rem;
        background: var(--bg); border-radius: 10px;
        font-size: 0.85rem; color: var(--muted);
      }
      .hours-list li { margin: 0.15rem 0; }

      .card-actions { display: flex; gap: 0.75rem; margin-top: 1.1rem; }
      .card-actions .btn-primary { flex: 1 1 auto; }
      .card-actions .btn-outline { flex: 0 0 auto; }

      .empty {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 16px;
        padding: 1.5rem;
        color: var(--muted);
        text-align: center;
      }
      .hidden { display: none; }
    </style>
    """
  end

  # -- Icons ----------------------------------------------------------------

  @icon_names [:pin, :locate, :map, :phone, :chevron]

  @doc """
  Inline SVG icon. `name` is one of #{inspect(@icon_names)}.
  """
  attr :name, :atom, required: true, values: @icon_names
  attr :size, :integer, default: 17

  def icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      {Phoenix.HTML.raw(icon_path(@name))}
    </svg>
    """
  end

  # Callers may pass the name as a literal string in HEEx; normalize to the
  # module's atoms.
  defp icon_path(name) when is_binary(name), do: icon_path(String.to_existing_atom(name))

  defp icon_path(:pin),
    do: ~S(<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" /><circle cx="12" cy="10" r="3" />)

  defp icon_path(:locate),
    do: ~S(<path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1" /><circle cx="12" cy="12" r="4" />)

  defp icon_path(:map),
    do: ~S(<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2Z" /><path d="M9 4v14M15 6v14" />)

  defp icon_path(:phone),
    do: ~S(<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92Z" />)

  defp icon_path(:chevron), do: ~S(<path d="m6 9 6 6 6-6" />)

  # -- Building blocks ------------------------------------------------------

  @doc """
  Human distance: under 1000 m → "850 m", otherwise kilometres with one
  decimal ("1.2 km").
  """
  def format_distance(m) when is_number(m) and m < 1000, do: "#{round(m)} m"
  def format_distance(m) when is_number(m), do: :erlang.float_to_binary(m / 1000, decimals: 1) <> " km"
  def format_distance(nil), do: ""

  @doc """
  Walking duration only, for the "~11 min walk" pill: "11 min", "< 1 min",
  or nil when the place has no routing summary.
  """
  def format_walk_duration(pharmacy) do
    case Map.get(pharmacy, :walk_duration_s) do
      s when is_number(s) and s < 60 -> "< 1 min"
      s when is_number(s) -> "#{round(s / 60)} min"
      _ -> nil
    end
  end

  @doc """
  Radius chip: a styled link, `active` marks the value currently in effect.
  """
  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false

  def chip(assigns) do
    ~H"""
    <.link class={if @active, do: "chip active", else: "chip"} href={@href} method="get">
      {@label}
    </.link>
    """
  end

  @doc """
  Distance pill: "919 m • ~11 min walk". Walk part omitted without a
  routing summary.
  """
  attr :pharmacy, Pharmacies, required: true

  def distance_pill(assigns) do
    ~H"""
    <span class="distance-pill">
      <strong>{format_distance(@pharmacy.distance_m)}</strong>
      <%= if walk = format_walk_duration(@pharmacy) do %>
        <span>•</span>
        <span>~{walk} walk</span>
      <% end %>
    </span>
    """
  end

  @doc """
  Open/closed status pill: "Open until 16:00" (green), "Open now" (green),
  "Closed" (red), or "Hours unavailable" (neutral) when hours are unknown.
  """
  attr :open_now, :boolean, required: true
  attr :closes_at, :string, default: nil

  def status_pill(assigns) do
    ~H"""
    <%= cond do %>
      <% @open_now == true and is_binary(@closes_at) and @closes_at != "" -> %>
        <span class="open-pill">Open until {@closes_at}</span>
      <% @open_now == true -> %>
        <span class="open-pill">Open now</span>
      <% @open_now == false -> %>
        <span class="open-pill closed">Closed</span>
      <% true -> %>
        <span class="open-pill unknown">Hours unavailable</span>
    <% end %>
    """
  end

  @doc """
  Collapsible "View all hours" block; renders nothing without hours.
  """
  attr :hours, :list, required: true

  def hours_details(assigns) do
    ~H"""
    <%= if is_list(@hours) and @hours != [] do %>
      <details class="hours-details">
        <summary>
          View all hours
          <.icon name="chevron" size={14} />
        </summary>
        <ul class="hours-list">
          <%= for h <- @hours do %>
            <li>{h}</li>
          <% end %>
        </ul>
      </details>
    <% end %>
    """
  end

  @doc """
  Card actions: Get Directions (Google Maps deep link, new tab) plus an
  outlined Call button when the pharmacy has a phone number.
  """
  attr :lat, :float, required: true
  attr :lng, :float, required: true
  attr :phone, :string, default: nil

  def card_actions(assigns) do
    ~H"""
    <div class="card-actions">
      <a
        class="btn btn-primary"
        href={"https://www.google.com/maps/dir/?api=1&destination=#{@lat},#{@lng}"}
        target="_blank"
        rel="noopener"
      >
        <.icon name="map" />
        Get Directions
      </a>
      <%= if @phone do %>
        <a class="btn btn-outline" href={"tel:" <> String.replace(@phone, " ", "")}>
          <.icon name="phone" />
          Call
        </a>
      <% end %>
    </div>
    """
  end

  # -- Composite ------------------------------------------------------------

  @doc """
  One pharmacy result card: name, distance/walk pill, address, hours row,
  actions.
  """
  attr :pharmacy, Pharmacies, required: true

  def pharmacy_card(assigns) do
    ~H"""
    <article class="card">
      <div class="card-top">
        <h2 class="card-name">{@pharmacy.display_name}</h2>
        <.distance_pill pharmacy={@pharmacy} />
      </div>
      <%= if @pharmacy.address do %>
        <div class="card-address">
          <.icon name="pin" size={15} />
          <span>{@pharmacy.address}</span>
        </div>
      <% end %>

      <hr class="card-divider" />

      <div class="hours-row">
        <.status_pill open_now={@pharmacy.open_now} closes_at={@pharmacy.closes_at} />
        <.hours_details hours={@pharmacy.opening_hours} />
      </div>

      <.card_actions lat={@pharmacy.lat} lng={@pharmacy.lng} phone={@pharmacy.phone_number} />
    </article>
    """
  end
end
