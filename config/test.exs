import Config

# Test database configuration
config :whispr_notification, WhisprNotifications.Repo,
  username: "postgres",
  password: "password",
  hostname: "localhost",
  database: "whispr_notification_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# HTTP endpoint for tests
config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4012],
  secret_key_base: "test_secret_key_base_notification_service",
  server: false

# gRPC port for tests
config :whispr_notification,
  grpc_port: 40012

# Quieter logging in tests
config :logger, level: :warning
