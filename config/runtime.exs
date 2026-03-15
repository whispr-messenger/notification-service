import Config

if config_env() == :prod do
  config :whispr_notification, WhisprNotificationsWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("HTTP_PORT", "4011"))
    ],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    url: [
      host: System.get_env("PHX_HOST", "localhost"),
      port: 443,
      scheme: "https"
    ],
    check_origin: false,
    server: true

  config :whispr_notification, :redis,
    host: System.get_env("REDIS_HOST", "localhost"),
    port: String.to_integer(System.get_env("REDIS_PORT", "6379")),
    database: String.to_integer(System.get_env("REDIS_DB", "0")),
    password: System.get_env("REDIS_PASSWORD"),
    timeout: 15_000,
    ssl: System.get_env("REDIS_SSL", "false") == "true"

  config :whispr_notification,
    grpc_port: String.to_integer(System.get_env("GRPC_PORT", "40011"))
end
