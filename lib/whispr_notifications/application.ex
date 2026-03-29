defmodule WhisprNotifications.Application do
  @moduledoc """
  OTP application pour le domaine de notifications.
  Démarre les superviseurs nécessaires (PubSub, Endpoint HTTP, cache devices, workers, etc.).
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # PubSub — must start before the Endpoint
      {Phoenix.PubSub, name: WhisprNotifications.PubSub},
      # Phoenix HTTP endpoint — binds the HTTP port declared in config
      WhisprNotificationsWeb.Endpoint,
      # Domain supervisors/workers
      {WhisprNotifications.Devices.CacheManager, []},
      {WhisprNotifications.Workers.TokenRefresher, []},
      {WhisprNotifications.Workers.CacheSyncWorker, []},
      {WhisprNotifications.Workers.CleanupWorker, []},
      {WhisprNotifications.Workers.MetricsWorker, []}
    ]

    opts = [strategy: :one_for_one, name: WhisprNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Required by Phoenix to reload configuration on config_change/3
  @impl true
  def config_change(changed, _new, removed) do
    WhisprNotificationsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
