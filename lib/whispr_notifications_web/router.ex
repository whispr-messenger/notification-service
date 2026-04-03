defmodule WhisprNotificationsWeb.Router do
  use WhisprNotificationsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :jwt_authenticated do
    plug WhisprNotificationsWeb.Plugs.Authenticate
  end

  scope "/api", WhisprNotificationsWeb do
    pipe_through :api

    # Gestion des réglages de notifications
    resources "/settings", SettingsController, only: [:show, :update], param: "user_id"

    # Mute / unmute conversation
    post "/conversations/:conversation_id/mute", MuteController, :mute
    delete "/conversations/:conversation_id/mute", MuteController, :unmute

    # Health check simple
    get "/v1/health", HealthController, :live
  end

  scope "/api", WhisprNotificationsWeb do
    pipe_through [:api, :jwt_authenticated]
    get "/v1/auth-check", AuthCheckController, :show
    post "/v1/notifications", NotificationsController, :create
  end
end
