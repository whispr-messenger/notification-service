defmodule WhisprNotifications.Application do
  @moduledoc """
  OTP application for the notification service.
  Starts the Repo, HTTP endpoint, cache managers, and background workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      WhisprNotifications.Repo,

      # PubSub for internal event broadcasting
      {Phoenix.PubSub, name: WhisprNotifications.PubSub},

      # HTTP endpoint
      WhisprNotificationsWeb.Endpoint,

      # Device cache
      {WhisprNotifications.Devices.CacheManager, []},

      # Background workers
      {WhisprNotifications.Workers.TokenRefresher, []},
      {WhisprNotifications.Workers.CacheSyncWorker, []},
      {WhisprNotifications.Workers.CleanupWorker, []},
      {WhisprNotifications.Workers.MetricsWorker, []}
    ]

    opts = [strategy: :one_for_one, name: WhisprNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WhisprNotificationsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
