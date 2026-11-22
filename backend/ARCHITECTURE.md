# PharmacyApp Backend — Architecture

Elixir/Phoenix service that finds pharmacies near a user's location using the **Google Places API (New)**. Serves a JSON API at `GET /api/pharmacies` and a server-rendered HTML page at `GET /`. No database, no session, no JS build step: every request is validate → provider call → transform → respond.

- **Runtime**: Elixir 1.20.5 / Erlang OTP 29 (pinned in `.tool-versions`, managed with asdf)
- **HTTP server**: Bandit (`Bandit.PhoenixAdapter`)
- **Places client**: vendored, generated [`googly_places`](vendor/googly_places) (path dep; Req ~> 0.6 + Jason underneath — do not edit)
- **State**: two public ETS tables (geocode cache, rate-limit counters) owned by supervised GenServers
- **Absences by design**: no Ecto/Repo, no PubSub/channels, no job scheduler (Oban/Broadway), no CI — persistence-free request/response service with only periodic ETS sweeps as background work

## Layering

Three strict layers; dependencies point downward only. The web layer never touches `Googly.*` structs, the domain never does I/O, and only the adapter knows about Google.

```
┌───────────────────────────── Web (pharmacy_app_web) ─────────────────────────────┐
│ Endpoint · Router · RateLimit plug · Params parser                               │
│ PharmaciesController (JSON) / PageController (HTML) → serialize + error mapping  │
└──────────────────────────────────┬───────────────────────────────────────────────┘
                                   │ %Params → params/opts
┌──────────────────────────────────▼───────────────────────────────────────────────┐
│ Service (pharmacies/service.ex) — orchestration only                             │
│ validate → cached geocode → adapter call → distance/filter/sort                  │
└──────────────┬──────────────────────────────────────────────┬────────────────────┘
               │                                              │
┌──────────────▼───────────────┐              ┌───────────────▼────────────────────┐
│ Pharmacies (pure domain)     │              │ PlacesAdapter (provider boundary)  │
│ validation, haversine,       │  %Pharmacy{} │ Googly calls, field masks,         │
│ filter, sort                 │◄─────────────│ translation, telemetry, timeouts   │
└──────────────────────────────┘              └───────────────┬────────────────────┘
                                                              │
                                              ┌───────────────▼────────────────────┐
                                              │ Googly.Places (vendored, Req)      │
                                              │ → Google Places API (New)          │
                                              └────────────────────────────────────┘
```

`Pharmacy` (`lib/pharmacy_app/pharmacies/pharmacy.ex`) is the app-owned result struct passed between layers. `distance_m` is origin-dependent, so the adapter never fills it; the service computes it per request via the haversine formula.

## Supervision tree

`PharmacyApp.Application` starts a flat `:one_for_one` supervisor:

| Child | Role | Ordering constraint |
|---|---|---|
| `Pharmacies.Cache` | GenServer owning the `:pharmacy_cache` ETS table; sweeps expired entries every 10 s | Before Endpoint (requests read it) |
| `Web.RateLimit.Sweeper` | GenServer owning the `:pharmacy_rate_limit` ETS table; sweeps stale windows every 10 s | Explicitly before Endpoint — the plug fails open if the table is missing |
| `Web.Endpoint` | Phoenix/Bandit listener on port 4000 | Last |

No worker processes per request; all shared state is ETS (`read_concurrency` / `write_concurrency`), so request handling stays in the caller's process.

## Request flows

### Coordinate search — `GET /api/pharmacies?lat=..&lng=..[&radius_m=..]`

```mermaid
sequenceDiagram
    participant C as Client
    participant RL as RateLimit plug
    participant PC as PharmaciesController
    participant P as Params
    participant S as Service
    participant D as Pharmacies (domain)
    participant A as PlacesAdapter
    participant G as Google Places

    C->>RL: GET /api/pharmacies
    RL->>RL: ETS counter per IP + global; over limit? 429 + Retry-After
    RL->>PC: pass
    PC->>P: parse(params, conn)
    P-->>PC: %Params{origin: :coords, radius clamped, language from Accept-Language}
    PC->>S: search(%{lat, lng, radius_m, language_code})
    S->>D: validate_params/1 (bounds, clamp, BCP-47)
    S->>A: search_nearby(lat, lng, radius_m, language_code: ...)
    A->>G: Search Nearby (POST, field mask, receive_timeout 5 s)
    G-->>A: places + routingSummaries
    A-->>S: {:ok, [%Pharmacy{} without distance_m]}
    S->>D: haversine distance → filter(radius) → sort (open first, then nearest)
    S-->>PC: {:ok, pharmacies}
    PC-->>C: 200 JSON (explicit field list)
```

Upstream calls are **never cached** for the coordinate path — distance, filtering, and sorting are origin-dependent, and the provider query already ran with this request's exact origin and radius. Only the geocode result of the address path is cached.

### Address search — `GET /api/pharmacies?q=..`

1. `Params.parse/2` resolves origin precedence: explicit `lat`/`lng` always win over `q`; `q` is used only when both coordinates are absent. Radius and language are validated **before** any upstream call (fail fast).
2. `Service.search_by_address/2` checks the geocode cache (key: normalized address + language, TTL 60 s, monotonic-time expiry). On miss it calls `PlacesAdapter.geocode/2`, which runs a **Places Text Search** with `page_size: 1` (the vendored client has no separate geocode endpoint) and caches the resolved `{lat, lng, formatted_address}`.
3. The resolved coordinates are validated, then the same `run/2` pipeline as the coordinate path executes.

Return shape on success: `{:ok, %{lat, lng, formatted_address, pharmacies}}`; the controller projects only `pharmacies` into the same JSON list as the coordinate path.

## Module map

| Module | Responsibility |
|---|---|
| `PharmacyApp.Application` | Supervision tree |
| `Pharmacies` | Pure domain: param validation, radius clamping (1–50 000 m, default 1 000), `filter/2`, `sort/2` (open first, then distance), haversine. No I/O. |
| `Pharmacies.Service` | Orchestration only. All collaborators (`:client`, `:geocoder`, `:cache`) are injectable opts for testing. |
| `Pharmacies.Cache` | ETS TTL cache for geocode results (60 s); normalized-address + language key; monotonic clock so entries don't survive wall-clock changes. |
| `Pharmacies.PlacesAdapter` | The **only** module touching `Googly.*`: builds requests (field masks, `DISTANCE` rank, WALK routing parameters), pairs places with routing summaries by position, translates to `%Pharmacy{}` (`closes_at` from `nextCloseTime` shifted by `utcOffsetMinutes`, walk duration parsing), emits telemetry, sets `receive_timeout` (default 5 000 ms, config `:places_receive_timeout`). Public `to_pharmacies/2`, `from_place/1`, `put_walk/2` make translation testable without network. |
| `Pharmacies.Pharmacy` | Result struct; `distance_m` nil until the service fills it. |
| `Web.Endpoint` | Plug stack; drops `q`/`lat`/`lng` from Phoenix parameter logging (location privacy; documented limitation: `Plug.Logger`'s raw request line still carries the query string). |
| `Web.Router` | `:api` pipeline (JSON) → `PharmaciesController.index`; `:browser` pipeline (HTML) → `PageController.home`. Both pipelines run the rate-limit plug. |
| `Web.RateLimit` + `.Sweeper` | Per-IP and global fixed-window limiter (see below). |
| `Web.Params` | Single web-input parser shared by both controllers: origin precedence, radius policy (malformed → default, no error), language from first valid `Accept-Language` tag. Struct dispatch (`origin: :none | :coords | :address` + `issues`). |
| `Web.PharmaciesController` | Error mapping + explicit JSON serializer (fixed field list; internal fields can't leak). |
| `Web.PageController` + `components.ex` | Server-rendered search page, same `Params` → `Service` path, HTML error banners. |
| `Web.ErrorJSON` / `ErrorHTML` | Renders for requests raising before a controller (404/500). |
| `vendor/googly_places` | Generated Places client (path dep). |

## Cross-cutting

### Rate limiting (`Web.RateLimit`)

- **Mechanics**: atomic `:ets.update_counter` on key `{ip, window_id}` plus a shared `{:global, window_id}` counter. Fixed window (default 60 s); a boundary permits at most 2× the limit — accepted tradeoff for abuse protection on a single endpoint.
- **Limits**: 20/IP/window and 300 global/window; config `:pharmacy_app, :rate_limit` (`:limit`, `:global_limit`, `:window_ms`).
- **Scope**: only the bare `/` (no query string) is exempt, so health checks never consume quota; `/?q=…` and `/?lat=…` count like API requests.
- **Client IP trust chain**: `fly-client-ip` (set by the Fly proxy, not spoofable from outside Fly) → first `x-forwarded-for` entry → socket `remote_ip`. Unidentifiable origin is allowed through.
- **Deny**: 429 JSON `{"errors": ["rate limit exceeded"]}` + `Retry-After` (seconds to window rollover, computed on the monotonic clock).
- **Failure policy**: fails **open** if the ETS table is missing (`ArgumentError` rescue) — a limiter outage never takes the API down. Per-IP counts still increment when the global cap denies, so IP rotation earns no free retries.

### Caching (`Pharmacies.Cache`)

- Single key type: `geocode_key/2` = `{normalized_address, language_code}` (trimmed, lowercased, whitespace-collapsed). Only the **geocode** result is cached; nearby results are never cached.
- TTL 60 s using `System.monotonic_time(:millisecond)`; lazy expiry on read plus a GenServer sweep (10 s interval, `:cache_sweep_interval`).
- Public table, reads/writes from request processes; `rescue ArgumentError → :miss / :ok` keeps it safe against table lifecycle races.

### Error handling & HTTP mapping

The adapter normalizes every upstream failure to one of:

| Adapter error | Meaning |
|---|---|
| `{:error, :address_not_found}` | Google returned nothing usable |
| `{:error, {:upstream, status, message}}` | Google rejected the request (`Googly.Places.Error`) |
| `{:error, :upstream_unavailable}` | Network/transport failure |

`PharmaciesController` maps them (and domain `{:error, {:invalid_params, issues}}`) to:

| HTTP | Condition |
|---|---|
| `422` | invalid params (`issues` list in body) |
| `404` | `address_not_found` |
| Google `4xx` mirrored as-is | upstream client error |
| `502` | upstream `5xx`/unknown status, or `upstream_unavailable` |

The HTML page mirrors the same statuses with a banner; invalid web input renders 200 with inline per-field errors.

### Telemetry

Each adapter call emits `[:pharmacy_app, :places, :request, :start | :stop | :exception]`. Metadata is low-cardinality by design: operation name and outcome status (`:ok`, `:upstream`, `:unavailable`) — **never** addresses, coordinates, or upstream messages.

### Configuration

| Where | What |
|---|---|
| `config/config.exs` | Endpoint (Bandit, port 4000, `server: true`, dev-only secret), error renderers |
| `config/runtime.exs` | `google_api_key` from `GOOGLE_MAPS_API_KEY` — **hard-fails at boot** when missing (test env exempt) |
| `config/test.exs` | Port 4001, `server: false`, dummy key, fast cache sweep, rate limit effectively off |
| App env | `:rate_limit` opts, `:places_receive_timeout` (5 000 ms), `:cache_sweep_interval`, `:rate_limit_sweep_interval`, `:service_opts` (test-only injected fakes via `TestClient`) |

## Deployment

Live at `https://pharmacy-app.fly.dev` (noted in the root `README.md`).

- **Docker**: two stages, **same base image** (`hexpm/elixir:1.20.5-erlang-29.1.2-...-slim`) for both, so the release's bundled ERTS matches the runtime libssl. Deps layer (manifest + lock + vendored client) cached separately from source. No API key is ever baked into the image — `runtime.exs` reads it at boot; supply via `-e` / compose `.env`.
- **Release customization** (`rel/`): `env.sh.eex` exports Fly-specific distributed-Erlang env when `FLY_APP_NAME` is set (`DNS_CLUSTER_QUERY`, `RELEASE_NODE`, IPv6 `proto_dist`) — latent clustering for a future multi-machine setup; the current `fly.toml` runs a single `app` process. `rel/overlays/bin` ships the standard release `server` scripts.
- **Runtime stage**: copies `_build/prod/rel/pharmacy_app` (self-contained release with bundled ERTS), non-root `phoenix` user, `HEALTHCHECK` curling `GET /` (local-only, never touches Google). Port fixed at 4000 (no `PORT` indirection).
- **Fly.io** (`fly.toml`): region `arn`, `min_machines_running = 0` with auto stop/start, 512 MB / 1 CPU, connection hard/soft limit 1000, forced HTTPS. Fly's proxy sets `fly-client-ip`, which the rate limiter consumes.
- **docker-compose** (repo root): single `backend` service, host port must stay `4000`, key injected via `${GOOGLE_MAPS_API_KEY}` from shell or root `.env`.

## Testing

`mix test` runs fully offline: the service layer takes an injected fake client (`test/support/test_client.ex`, driven by `:test_client_fn` / `:test_geocoder_fn` under `:pharmacy_app, :service_opts`), and controller tests dispatch through the endpoint without opening a port. Suites cover the domain (`pharmacies_test`), service orchestration, adapter translation (`places_adapter_test` — no network), cache TTL/sweep, rate-limit windows and fail-open behavior, and both controllers.
