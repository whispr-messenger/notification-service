import Config

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4002"))],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_please_change_in_production"
