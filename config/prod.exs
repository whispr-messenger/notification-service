import Config

# ======================================================================
# Endpoint HTTP production
# ======================================================================

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT", "4002"))
  ],
  url: [
    host: System.get_env("PHX_HOST", "localhost"),
    port: 443,
    scheme: "https"
  ],
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  check_origin: false,
  server: true

# ======================================================================
# Redis production (pour cache devices / rate limiting, etc.)
# ======================================================================

config :whispr_notification, :redis,
  host: System.get_env("REDIS_HOST", "localhost"),
  port: String.to_integer(System.get_env("REDIS_PORT", "6379")),
  database: String.to_integer(System.get_env("REDIS_DB", "0")),
  password: System.get_env("REDIS_PASSWORD"),
  timeout: 15_000,
  ssl: System.get_env("REDIS_SSL", "false") == "true"

# ======================================================================
# gRPC port production
# ======================================================================

config :whispr_notification,
  grpc_port: String.to_integer(System.get_env("GRPC_PORT", "50053"))

# ======================================================================
# Logging production
# ======================================================================

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :conversation_id, :notification_id],
  level: :info

config :logger,
  level: :info

# ======================================================================
# Domain-specific settings (notifications)
# ======================================================================

config :whispr_notification, :notifications,
  retention_days:
    String.to_integer(System.get_env("NOTIF_RETENTION_DAYS", "90")),
  cleanup_batch_size:
    String.to_integer(System.get_env("NOTIF_CLEANUP_BATCH_SIZE", "1000"))

config :whispr_notification, :workers,
  metrics_interval:
    String.to_integer(System.get_env("METRICS_INTERVAL_MS", "60000")),
  cleanup_interval:
    String.to_integer(System.get_env("CLEANUP_INTERVAL_MS", "43200000")),
  cache_sync_interval:
    String.to_integer(System.get_env("CACHE_SYNC_INTERVAL_MS", "600000")),
  token_refresh_interval:
    String.to_integer(System.get_env("TOKEN_REFRESH_INTERVAL_MS", "3600000"))

# ======================================================================
# Désactiver routes dev en prod (si tu as un flag similaire)
# ======================================================================

config :whispr_notification, dev_routes: false
