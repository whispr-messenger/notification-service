defmodule WhisprNotificationsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :whispr_notification

  # Si tu veux du WebSocket plus tard (LiveView, etc.), tu l’ajouteras ici.

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:whispr_notification, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head

  plug WhisprNotificationsWeb.Router
end
