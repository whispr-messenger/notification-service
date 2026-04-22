defmodule WhisprNotificationsWeb.Router do
  use WhisprNotificationsWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :jwt_authenticated do
    plug(WhisprNotificationsWeb.Plugs.Authenticate)
  end

  # ── /api (when the gateway strips the /notification prefix) ──

  scope "/api", WhisprNotificationsWeb do
    pipe_through(:api)

    # Only the health probe stays open; everything else requires a JWT.
    get("/v1/health", HealthController, :live)
  end

  scope "/api", WhisprNotificationsWeb do
    pipe_through([:api, :jwt_authenticated])

    resources("/settings", SettingsController, only: [:show, :update])

    post("/conversations/:conversation_id/mute", MuteController, :mute)
    delete("/conversations/:conversation_id/mute", MuteController, :unmute)

    get("/v1/auth-check", AuthCheckController, :show)
    post("/v1/notifications", NotificationsController, :create)
    get("/v1/badge", BadgeController, :show)
    get("/v1/settings", SettingsController, :show)
    put("/v1/settings", SettingsController, :update)
  end

  # ── /notification/api (when the gateway forwards the full path) ──

  scope "/notification/api", WhisprNotificationsWeb do
    pipe_through(:api)

    get("/v1/health", HealthController, :live)
  end

  scope "/notification/api", WhisprNotificationsWeb do
    pipe_through([:api, :jwt_authenticated])

    resources("/settings", SettingsController, only: [:show, :update])

    post("/conversations/:conversation_id/mute", MuteController, :mute)
    delete("/conversations/:conversation_id/mute", MuteController, :unmute)

    get("/v1/auth-check", AuthCheckController, :show)
    post("/v1/notifications", NotificationsController, :create)
    get("/v1/badge", BadgeController, :show)
    get("/v1/settings", SettingsController, :show)
    put("/v1/settings", SettingsController, :update)
  end
end
