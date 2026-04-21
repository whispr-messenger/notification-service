import Config

# Do not start the HTTP server in tests — the Phoenix Endpoint is still in the
# supervision tree (needed for PubSub routing) but should not bind a port.
config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  server: false

config :whispr_notification, WhisprNotifications.Repo,
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.fetch_env!("DATABASE_USER"),
  password: System.fetch_env!("DATABASE_PASSWORD"),
  database:
    System.get_env(
      "DATABASE_NAME",
      "whispr_notification_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10"))
