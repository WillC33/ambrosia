defmodule Ambrosia.MixProject do
  use Mix.Project

  def project do
    [
      app: :ambrosia,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Metadata
      name: "Ambrosia",
      description: "A fault-tolerant, concurrent Gemini protocol server",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :crypto, :inets],
      mod: {Ambrosia.Application, []},
      env: [
        port: 1965,
        root_dir: "./gemini",
        cert_file: "./certs/cert.pem",
        key_file: "./certs/key.pem",
        max_connections: 1000,
        request_timeout: 10_000
      ]
    ]
  end

  defp deps do
    [
      # TCP acceptor pool
      {:ranch, "~> 2.1"},

      # Metrics and monitoring
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:plug, "~> 1.14"},
      {:plug_cowboy, "~> 2.6"},

      # Development
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["AGPL-3.0"],
      links: %{"Codeberg" => "https://codeberg.org/WillC33/ambrosia"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
