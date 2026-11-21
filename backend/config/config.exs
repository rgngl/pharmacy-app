import Config

config :pharmacy_app, PharmacyAppWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [port: 4000],
  server: true,
  secret_key_base: String.pad_trailing("pharmacy_secret_key_base_dev_only", 64, "0"),
  # Raised requests (e.g. NoRouteError for /favicon.ico) render via ErrorHTML.
  render_errors: [formats: [html: PharmacyAppWeb.ErrorHTML, json: PharmacyAppWeb.ErrorJSON], layout: false]

config :logger, level: :info

# Mix does not auto-import env-specific config files; test.exs must be explicit.
if config_env() == :test, do: import_config "test.exs"
