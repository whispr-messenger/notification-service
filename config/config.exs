import Config

# ======================================================================
# Application principale
# ======================================================================

config :whispr_notification,
  ecto_repos: [],
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
# Redis / cache devices (si utilisé)
# ======================================================================

config :whispr_notification, :redis,
  host: System.get_env("REDIS_HOST", "localhost"),
  port: String.to_integer(System.get_env("REDIS_PORT", "6379")),
  database: String.to_integer(System.get_env("REDIS_DB", "0")),
  password: System.get_env("REDIS_PASSWORD")

# ======================================================================
# gRPC
# ======================================================================

config :whispr_notification,
  grpc_port: String.to_integer(System.get_env("GRPC_PORT", "50053"))

# ======================================================================
# Notifications & workers (exemples de réglages domaine)
# ======================================================================

config :whispr_notification, :notifications,
  # nombre de jours à garder l’historique
  retention_days: String.to_integer(System.get_env("NOTIF_RETENTION_DAYS", "90")),
  # taille batch de cleanup
  cleanup_batch_size: String.to_integer(System.get_env("NOTIF_CLEANUP_BATCH_SIZE", "1000"))

config :whispr_notification, :workers,
  # fréquences en ms (tu peux ajuster avec tes @interval)
  metrics_interval: String.to_integer(System.get_env("METRICS_INTERVAL_MS", "60000")),
  cleanup_interval: String.to_integer(System.get_env("CLEANUP_INTERVAL_MS", "43200000")),
  cache_sync_interval: String.to_integer(System.get_env("CACHE_SYNC_INTERVAL_MS", "600000")),
  token_refresh_interval: String.to_integer(System.get_env("TOKEN_REFRESH_INTERVAL_MS", "3600000"))

# ======================================================================
# Inter-service communication
# ======================================================================

config :whispr_notification, :services,
  auth_service: %{
    host: System.get_env("AUTH_SERVICE_HOST", "auth-service"),
    port: String.to_integer(System.get_env("AUTH_SERVICE_PORT", "50056"))
  },
  messaging_service: %{
    host: System.get_env("MESSAGING_SERVICE_HOST", "messaging-service"),
    port: String.to_integer(System.get_env("MESSAGING_SERVICE_PORT", "50052"))
  },
  user_service: %{
    host: System.get_env("USER_SERVICE_HOST", "user-service"),
    port: String.to_integer(System.get_env("USER_SERVICE_PORT", "50055"))
  }

# ======================================================================
# FCM / APNS (Pigeon / Fcmex)
# ======================================================================


config :fcmex,
  project_id: System.get_env("FCM_PROJECT_ID"),
  json_keyfile: System.get_env("FCM_JSON_KEYFILE")

config :pigeon, :apns,
  apns_default: %{
    key: System.get_env("APNS_KEY_PATH"),
    key_identifier: System.get_env("APNS_KEY_ID"),
    team_id: System.get_env("APNS_TEAM_ID"),
    mode: String.to_atom(System.get_env("APNS_MODE", "dev")), # :dev ou :prod
    ping_interval: 600_000
  }

# ======================================================================
# Logger
# ======================================================================

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :conversation_id, :notification_id]

# ======================================================================
# Phoenix / JSON
# ======================================================================

config :phoenix_swagger, json_library: Jason

# Si tu as un module Telemetry dédié :
config :whispr_notification, WhisprNotificationsWeb.Telemetry, metrics: []

# ======================================================================
# Import des configs par environnement
# ======================================================================

import_config "#{config_env()}.exs"
