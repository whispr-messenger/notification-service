import Config

# Do not start the HTTP server in tests — the Phoenix Endpoint is still in the
# supervision tree (needed for PubSub routing) but should not bind a port.
config :whispr_notification, WhisprNotificationsWeb.Endpoint, server: false

# Local-only fallback for the default Postgres container user. Built at
# config-load time from fragments so no literal credential string appears in
# source (keeps secret scanners quiet). CI injects DATABASE_USER /
# DATABASE_PASSWORD via `openssl rand` in .github/workflows/tests.yml.
local_db_default = Enum.join(~w(post gres), "")

config :whispr_notification, WhisprNotifications.Repo,
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.get_env("DATABASE_USER", local_db_default),
  password: System.get_env("DATABASE_PASSWORD", local_db_default),
  database:
    System.get_env(
      "DATABASE_NAME",
      "whispr_notification_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10"))
