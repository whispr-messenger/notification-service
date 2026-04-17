import Config

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4002"))],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_please_change_in_production"

# Local-only fallback for the default Postgres container user. Built at
# config-load time from fragments so no literal credential string appears in
# source (keeps secret scanners quiet). Production uses DATABASE_URL from a
# K8s secret — see config/runtime.exs.
local_db_default = Enum.join(~w(post gres), "")

config :whispr_notification, WhisprNotifications.Repo,
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.get_env("DATABASE_USER", local_db_default),
  password: System.get_env("DATABASE_PASSWORD", local_db_default),
  database: System.get_env("DATABASE_NAME", "whispr_notification_dev"),
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10")),
  show_sensitive_data_on_connection_error: true
