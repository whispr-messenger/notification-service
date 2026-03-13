import Config

# Database configuration
config :whispr_notification, WhisprNotifications.Repo,
  username: "postgres",
  password: "password",
  hostname: "localhost",
  database: "whispr_notification_dev",
  port: 5432,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  log: :debug

# HTTP endpoint on port 4011
config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4011],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_notification_service_change_in_production",
  watchers: []

# gRPC on port 40011
config :whispr_notification,
  grpc_port: 40011

# Development Redis
config :whispr_notification, :redis,
  host: "localhost",
  port: 6379,
  database: 0,
  timeout: 5000

# Enable dev routes
config :whispr_notification, dev_routes: true

# Development logging
config :logger, :console,
  format: "[$level] $message\n",
  level: :debug

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
