import Config

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4002"))],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_please_change_in_production"

config :whispr_notification, WhisprNotifications.Repo,
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  database: System.get_env("DATABASE_NAME", "whispr_notification_dev"),
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10")),
  show_sensitive_data_on_connection_error: true
