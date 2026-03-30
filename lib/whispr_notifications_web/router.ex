defmodule WhisprNotificationsWeb.Router do
  use WhisprNotificationsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WhisprNotificationsWeb do
    pipe_through :api

    # Gestion des réglages de notifications
    resources "/settings", SettingsController, only: [:show, :update]

    # Mute / unmute conversation
    post "/conversations/:conversation_id/mute", MuteController, :mute
    delete "/conversations/:conversation_id/mute", MuteController, :unmute

    # Health check simple
    get "/v1/health", HealthController, :live
  end

  scope "/notification/api", WhisprNotificationsWeb do
    pipe_through :api

    resources "/settings", SettingsController, only: [:show, :update]
    post "/conversations/:conversation_id/mute", MuteController, :mute
    delete "/conversations/:conversation_id/mute", MuteController, :unmute
    get "/v1/health", HealthController, :live
  end

  scope "/", WhisprNotificationsWeb do
    pipe_through :api

    get "/metrics", HealthController, :metrics
  end

  scope "/notification", WhisprNotificationsWeb do
    pipe_through :api

    get "/metrics", HealthController, :metrics
  end
end
