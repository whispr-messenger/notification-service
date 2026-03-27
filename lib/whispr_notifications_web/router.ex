defmodule WhisprNotificationsWeb.Router do
  use WhisprNotificationsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_protected do
    plug :accepts, ["json"]
    plug WhisprNotificationsWeb.Plugs.AuthenticateJwt
  end

  scope "/api/v1", WhisprNotificationsWeb do
    pipe_through :api

    # Health check
    get "/health", HealthController, :live
  end

  scope "/api/v1", WhisprNotificationsWeb do
    pipe_through :api_protected

    # Device token registration
    get "/devices", DeviceController, :index
    post "/devices", DeviceController, :create
    delete "/devices/:device_id", DeviceController, :delete

    # Notification settings
    get "/notifications/settings", SettingsController, :show
    patch "/notifications/settings", SettingsController, :update

    # Per-conversation mute/unmute
    post "/conversations/:id/mute", MuteController, :mute
    delete "/conversations/:id/mute", MuteController, :unmute

    # Auth check (integration tests)
    get "/auth-check", HealthController, :auth_check
  end
end
