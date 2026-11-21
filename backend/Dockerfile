# syntax=docker/dockerfile:1
#
# Version note: backend/.tool-versions pins `erlang 29.1.2` and
# `elixir 1.20.5-otp-29`. hexpm/elixir publishes an exact tag for that pair:
#   hexpm/elixir:1.20.5-erlang-29.1.2-debian-bookworm-20261104-slim
# If this tag disappears, pick the closest
# hexpm/elixir:1.20.5-erlang-29.1.x-debian-*-slim tag (same Elixir, same
# OTP-29 line) and note the drift here.
#
# The same image is reused for both stages on purpose: the prod release
# bundles its own ERTS, and reusing the identical Debian base guarantees the
# bundled erts/libssl match the runtime. `mix release` defaults to
# include_erts: true, so the runtime stage needs no Elixir toolchain at all —
# it only needs the bundled runtime files from _build/prod/rel.

# ---------------------------------------------------------------------------
# Stage 1 — build
# ---------------------------------------------------------------------------
# This stage compiles with MIX_ENV=prod. GOOGLE_MAPS_API_KEY is deliberately
# NOT set here: config/runtime.exs reads it via System.fetch_env! at boot,
# which is a runtime concern, not a build concern. No key is ever baked into
# the image; supply it with `docker run -e` or docker-compose `environment`.
FROM hexpm/elixir:1.20.5-erlang-29.1.2-debian-bookworm-20261104-slim AS build

ENV MIX_ENV=prod
WORKDIR /app

# Layer 1: manifest + lock + vendored path dep, so `mix deps.get` is cached
# unless the dependency set changes.
# mix.exs declares {:googly_places, path: "vendor/googly_places"}; its own
# deps are fetched as part of the same `mix deps.get`.
COPY mix.exs mix.lock ./
COPY vendor/googly_places vendor/googly_places
RUN mix deps.get

# Layer 2: application source.
# (test/ and host artifacts are excluded via .dockerignore.)
COPY lib lib
COPY config config

# Compile first so a compile error surfaces in a cached, cheap layer; then
# produce the self-contained release in _build/prod/rel/pharmacy_app.
RUN mix compile
RUN mix release

# ---------------------------------------------------------------------------
# Stage 2 — runtime
# ---------------------------------------------------------------------------
FROM hexpm/elixir:1.20.5-erlang-29.1.2-debian-bookworm-20261104-slim AS runtime

# curl is only for the container HEALTHCHECK on the `GET /` route; the image
# ships without any HTTP client.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Non-root user per Phoenix release convention. UID/GID fixed for clarity.
RUN groupadd -g 1000 phoenix \
  && useradd -m -u 1000 -g phoenix phoenix

WORKDIR /app
COPY --from=build --chown=phoenix:phoenix /app/_build/prod/rel/pharmacy_app ./

# server: true is already set in config/config.exs; PHX_SERVER is set anyway
# so the release behaves as a server even if config drifts to the Phoenix
# default (server: false).
ENV PHX_SERVER=true

# The listen port is fixed at 4000 in config/config.exs (no `{:system, "PORT"}`
# indirection), so the image does not honour PORT at runtime.
EXPOSE 4000

USER phoenix

# Optional healthcheck against GET / (router also serves /api/pharmacies, but
# that can reach out to the Google API; / is local-only).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:4000/ -o /dev/null || exit 1

# Entry point of the mix release (`bin/pharmacy_app start` is equivalent).
CMD ["/app/bin/pharmacy_app", "start"]
