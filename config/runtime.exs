import Config

# Hard-fail at boot when the API key is missing (test env provides its own).
if config_env() != :test do
  config :pharmacy_app, google_api_key: System.fetch_env!("GOOGLE_MAPS_API_KEY")
end
