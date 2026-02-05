defmodule WhisprNotification.MixProject do
  use Mix.Project

  def project do
    [
      app: :whispr_notification,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      elixirc_options: [warnings_as_errors: false],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.xml": :test
      ]
    ]
  end

  def application do
    [
      mod: {WhisprNotifications.Application, []},
      extra_applications: [:logger, :runtime_tools, :grpcbox]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:plug_cowboy, "~> 2.6"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:redix, "~> 1.2"},
      {:grpcbox, "~> 0.17"},
      {:protobuf, "~> 0.12"},
      {:jason, "~> 1.4"},
      {:poison, "~> 6.0"},
      {:req, "~> 0.5"},
      {:elixir_uuid, "~> 1.2"},
      {:pigeon, "~> 2.0"},
      {:fcmex, "~> 0.6"},
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:phoenix_swagger, "~> 0.8"},
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
