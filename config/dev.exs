import Config

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4002],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_please_change_in_production"
