import Config

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4002"))],
  url: [host: System.get_env("PHX_HOST", "localhost"), port: 4002],
  secret_key_base:
    System.get_env("SECRET_KEY_BASE", "development_secret_key_base_please_change_in_production"),
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  server: true
