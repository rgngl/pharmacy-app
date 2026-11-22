# PharmacyApp

Finds the nearest pharmacies for a user's coordinates using the Google Places API.

Elixir 1.20.5-otp-29 / Erlang/OTP 29, managed with [asdf](https://asdf-vm.com). Layered design: Phoenix transport → service orchestration → pure domain logic, with a vendored generated Google Places client (`vendor/googly_places`).

## Prerequisites

- asdf with the `erlang` and `elixir` plugins. Versions are pinned in `.tool-versions`:

  ```sh
  asdf install          # installs erlang 29.1.2 and elixir 1.20.5-otp-29
  ```

- Make sure `~/.asdf/shims` is on your `PATH` (fish: `fish_add_path ~/.asdf/shims`, one-time and persistent).

- A Google Maps API key with the **Places API** enabled (Places API (New) endpoints are used).

## Setup

```sh
mix deps.get
```

## Running the server

```sh
GOOGLE_MAPS_API_KEY=your-key-here mix phx.server
```

The app fails to boot without `GOOGLE_MAPS_API_KEY` (checked at startup in `config/runtime.exs`).

The server listens on `http://localhost:4000`. To run it interactively with an IEx shell attached:

```sh
GOOGLE_MAPS_API_KEY=your-key-here iex -S mix phx.server
```

## Using the API

```sh
curl 'http://localhost:4000/api/pharmacies?lat=52.52&lng=13.405&radius_m=2000'
```

Query parameters:

| Param     | Required                       | Meaning                                        |
|-----------|--------------------------------|------------------------------------------------|
| `lat`     | yes, unless `q` is given       | User latitude, -90 to 90                       |
| `lng`     | yes, unless `q` is given       | User longitude, -180 to 180                    |
| `q`       | yes, unless `lat`/`lng` given  | Free-form address; geocoded via Places Text Search, then searched around the top hit. Explicit `lat`/`lng` win when both are sent. |
| `radius_m`| no (default 1000)              | Search radius in meters, clamped to 1–50 000   |

Responses:

- `200` — JSON list of pharmacies: `id`, `display_name`, `address`, `lat`, `lng`, `distance_m` (computed locally via haversine), `open_now`, `opening_hours`.
- `422` — invalid parameters; body includes an issue list.
- `404` — `q` given but Google returned no matching address.
- `4xx` / `502` — upstream (Google) error, mirrored or mapped by the controller.

Results are cached for 60 s on a ~100 m location grid; geocode results are cached for 60 s per normalized address and language.

### Rate limiting

`GET /api/pharmacies` is rate limited per client IP — 20 requests per 60 s window, then `429` with a `Retry-After` header until the window rolls over — and by a global ceiling of 300 requests per window across all IPs, so a coordinated flood from many rotating IPs still trips it. The same limits apply to the HTML page (`GET /`) whenever it carries search parameters (`?q=…` / `?lat=…`), because those trigger Google calls; only the bare `/` — what health checks curl — is exempt. The client IP is the `fly-client-ip` header set by the Fly proxy (not spoofable from outside Fly), with `x-forwarded-for` / socket address fallbacks for local development.

Limits are configured under `:pharmacy_app, :rate_limit` (`:limit`, `:global_limit`, `:window_ms`); defaults live in `lib/pharmacy_app_web/rate_limit.ex`. The limiter fails open if its ETS table is missing, so a limiter outage never takes the API down.

### Google API spend protection

Two layers, both independent of the rate limiter:

- **Cloud Console quotas**: cap the Places API key's daily request quota and restrict the key (server IP or referrer) in Google Cloud Console. With a cap, sustained abuse ends in Google `429`s instead of billing.
- **60 s result caches** (above) absorb repeated identical searches.

## Web UI

A server-rendered page at `GET /` (HTML, no JS build step — the script is inline in the HEEx template, styles ship via the `<.stylesheet />` component) shows nearby pharmacies with distance, open-now status, and opening hours. Reusable pieces (cards, pills, chips, icons) live in `lib/pharmacy_app_web/components/components.ex` as `Phoenix.Component` function components.

Two ways to set the search origin:

- **Address box** — a free-form address submitted as `?q=…`. The server geocodes it (Places Text Search, top hit), then searches pharmacies around the resolved point. The resolved address is shown above the results ("Showing pharmacies near …") and the radius chips re-submit with the same `q`; the geocode result is cached, so chip clicks don't re-bill a Text Search. A non-matching address shows a "Couldn't find an address matching …" banner instead of results.
- **Use my location** — a button that asks the browser's Geolocation API and reloads with `?lat=..&lng=..` (dropping any `q`). While locating, a "Detecting your location…" state is shown; if permission is denied, the fix fails, or the request times out, an error message with a **Retry** button appears. Geolocation requires a secure context: if the page is opened over plain HTTP without geolocation support, it asks you to retry over HTTPS — or to pass coordinates manually as `?lat=&lng=` (with optional `radius_m`), which remains a supported fallback.

Unlike the earlier version, the page no longer auto-locates on load; nothing is fetched until you search by address or click "Use my location". Radius presets (500 m / 1 km / 2 km / 5 km) appear as links next to the results; the default is 1000 m. Invalid input shows inline errors, and upstream (Google) failures show a banner, mirroring the JSON API's status codes.

## Tests

```sh
mix test
```

Tests are fully offline: the service layer uses an injected fake Places client, transport tests dispatch through the endpoint without opening a port. A real API key is not needed.

## Project layout

```
lib/pharmacy_app/
  pharmacies/pharmacy.ex         # pure domain: validation, haversine, Google model → app struct
  pharmacies/places_adapter.ex   # only module that touches Googly.Places.* (API key, error translation)
  pharmacies/service.ex          # orchestration: validate → cache → client → map/filter/sort
  pharmacies/cache.ex            # ETS + GenServer TTL cache (60 s, ~100 m grid)
  application.ex                 # supervisor: Cache + RateLimit sweeper + Endpoint
lib/pharmacy_app_web/
  endpoint.ex, router.ex         # GET /api/pharmacies
  rate_limit.ex                  # per-IP fixed-window limiter (429 + Retry-After)
  controllers/pharmacies_controller.ex
vendor/googly_places/            # generated Google Places client (do not edit)
```

## Regenerating the Places client

The client is generated from Google's discovery document with [googly](https://github.com/Rabbet/googly). To regenerate after a Google API update:

```sh
cd ../googly && mix googly.generate Places   # manifest entry: config/apis.json
cp -r clients/googly_places ../pharmacy-app/vendor/
```
