import Config

# Kubernetes service env vars can be exposed either as plain ports ("3001")
# or full URIs ("tcp://10.x.x.x:3001"). Normalize both forms.
parse_port = fn value ->
  case URI.parse(value) do
    %URI{port: port} when is_integer(port) -> port
    _ -> String.to_integer(value)
  end
end

# ======================================================================
# Application principale
# ======================================================================

config :whispr_notification,
  env: config_env(),
  ecto_repos: [WhisprNotifications.Repo],
  generators: [binary_id: true]

# ======================================================================
# Endpoint HTTP (Phoenix)
# ======================================================================

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: WhisprNotificationsWeb.ErrorHTML, json: WhisprNotificationsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WhisprNotifications.PubSub,
  live_view: [signing_salt: "notifications_secret"],
  server: true

# ======================================================================

# ======================================================================
# gRPC
# ======================================================================

config :whispr_notification,
  grpc_port: parse_port.(System.get_env("GRPC_PORT", "50053"))

# ======================================================================
# Notifications & workers
# ======================================================================

config :whispr_notification, :notifications,
  retention_days: String.to_integer(System.get_env("NOTIF_RETENTION_DAYS", "90")),
  cleanup_batch_size: String.to_integer(System.get_env("NOTIF_CLEANUP_BATCH_SIZE", "1000"))

config :whispr_notification, :workers,
  metrics_interval: String.to_integer(System.get_env("METRICS_INTERVAL_MS", "60000")),
  cleanup_interval: String.to_integer(System.get_env("CLEANUP_INTERVAL_MS", "43200000")),
  cache_sync_interval: String.to_integer(System.get_env("CACHE_SYNC_INTERVAL_MS", "600000")),
  token_refresh_interval:
    String.to_integer(System.get_env("TOKEN_REFRESH_INTERVAL_MS", "3600000"))

# ======================================================================
# Inter-service communication
# ======================================================================

config :whispr_notification, :services,
  auth_service: %{
    host: System.get_env("AUTH_SERVICE_HOST", "auth-service"),
    port: parse_port.(System.get_env("AUTH_SERVICE_PORT", "50056"))
  },
  messaging_service: %{
    host: System.get_env("MESSAGING_SERVICE_HOST", "messaging-service"),
    port: parse_port.(System.get_env("MESSAGING_SERVICE_PORT", "50052"))
  },
  user_service: %{
    host: System.get_env("USER_SERVICE_HOST", "user-service"),
    port: parse_port.(System.get_env("USER_SERVICE_PORT", "50055"))
  }

# ======================================================================
# FCM / APNS
# ======================================================================
#
# FCM HTTP v1 — configured via `config :whispr_notification, :fcm` in
# runtime.exs (OAuth via Goth). The project_id/service-account JSON
# default to FCM_PROJECT_ID / FCM_JSON_KEYFILE env vars.
#
# APNS HTTP/2 — configured via `config :whispr_notification, :apns`
# (and the per-dispatcher `WhisprNotifications.Delivery.ApnsDispatcher`
# block) in runtime.exs from APNS_KEY_PATH / APNS_KEY_ID / APNS_TEAM_ID
# / APNS_MODE.

# ======================================================================
# Web Push VAPID
# ======================================================================
#
# Les clés VAPID viennent des secrets Kubernetes et ne sont pas disponibles
# au build Docker. La config :web_push_elixir est dans runtime.exs pour que
# System.get_env soit évalué au démarrage du pod, pas lors du mix release.
# En dev/CI les clés sont absentes — le WebPushClient retourne :not_configured.

# ======================================================================
# Logger
# ======================================================================

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :user_id,
    :conversation_id,
    :notification_id,
    :report_id,
    :appeal_id,
    :reported_user_id
  ]

# ======================================================================
# Phoenix / JSON
# ======================================================================

config :phoenix_swagger, json_library: Jason
config :whispr_notification, WhisprNotificationsWeb.Telemetry, metrics: []

# ======================================================================
# Import des configs par environnement
# ======================================================================

import_config "#{config_env()}.exs"
