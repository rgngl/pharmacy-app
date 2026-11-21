defmodule PharmacyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :pharmacy_app,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {PharmacyApp.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:googly_places, path: "vendor/googly_places"},
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.6"},
      {:jason, "~> 1.4"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"}
    ]
  end
end
