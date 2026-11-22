import Config

config :pharmacy_app, PharmacyAppWeb.Endpoint,
  http: [port: 4001],
  server: false

config :pharmacy_app, google_api_key: "test-dummy-key"
config :pharmacy_app, cache_sweep_interval: 200

# Controller tests hit /api/pharmacies freely; the rate-limit tests override
# this per-test with a tight limit and clear the table in setup.
config :pharmacy_app, rate_limit: [limit: 1_000_000, window_ms: 60_000]

config :logger, level: :warning
