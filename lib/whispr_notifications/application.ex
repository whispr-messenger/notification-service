defmodule WhisprNotifications.Application do
  @moduledoc """
  OTP application pour le domaine de notifications.
  Démarre les superviseurs nécessaires (cache devices, workers, etc.).
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Exemples de superviseurs/GenServers de ton domaine
      {WhisprNotifications.Devices.CacheManager, []},
      {WhisprNotifications.Workers.TokenRefresher, []},
      {WhisprNotifications.Workers.CacheSyncWorker, []},
      {WhisprNotifications.Workers.CleanupWorker, []},
      {WhisprNotifications.Workers.MetricsWorker, []}
    ]

    opts = [strategy: :one_for_one, name: WhisprNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
