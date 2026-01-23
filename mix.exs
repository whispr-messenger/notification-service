defmodule WhisprNotification.MixProject do
  use Mix.Project

  def project do
    [
      app: :whispr_notification,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
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
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:redix, "~> 1.2"},
      {:grpcbox, "~> 0.17"},
      {:protobuf, "~> 0.12"},
      {:jason, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:pigeon, "~> 2.0"},   # APNS push notifications
      {:fcmex, "~> 0.6"},    # FCM notifications
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:req, "~> 0.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # {:ex_doc, ">= 0.30.0", only: :dev, runtime: false},
      # {:earmark_parser, "~> 1.4.42", only: [:dev, :test], runtime: false, override: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
