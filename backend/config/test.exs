import Config

config :pharmacy_app, PharmacyAppWeb.Endpoint,
  http: [port: 4001],
  server: false

config :pharmacy_app, google_api_key: "test-dummy-key"
config :pharmacy_app, cache_sweep_interval: 200

config :logger, level: :warning
