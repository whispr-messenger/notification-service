defmodule WhisprNotifications.Application do
  @moduledoc """
  OTP application for the notification service.
  Starts the Repo, HTTP endpoint, cache managers, and background workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
      # Database
      WhisprNotifications.Repo,

      # PubSub for internal event broadcasting
      {Phoenix.PubSub, name: WhisprNotifications.PubSub},

      # HTTP endpoint
      WhisprNotificationsWeb.Endpoint,

      # Device cache
      {WhisprNotifications.Devices.CacheManager, []},

      # JWT JWKS cache
      {WhisprNotifications.Auth.JwksCache, []},

      # Background workers
      {WhisprNotifications.Workers.TokenRefresher, []},
      {WhisprNotifications.Workers.CacheSyncWorker, []},
      {WhisprNotifications.Workers.CleanupWorker, []},
      {WhisprNotifications.Workers.MetricsWorker, []}
    ]
      |> maybe_add_apns_dispatcher()

    opts = [strategy: :one_for_one, name: WhisprNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WhisprNotificationsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_apns_dispatcher(children) do
    if apns_configured?() do
      [WhisprNotifications.APNS | children]
    else
      children
    end
  end

  defp apns_configured? do
    config = Application.get_env(:whispr_notification, WhisprNotifications.APNS, [])

    is_binary(Keyword.get(config, :key)) and Keyword.get(config, :key) != "" and
      is_binary(Keyword.get(config, :key_identifier)) and Keyword.get(config, :key_identifier) != "" and
      is_binary(Keyword.get(config, :team_id)) and Keyword.get(config, :team_id) != ""
  end
end
