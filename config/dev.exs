import Config

config :whispr_notification, WhisprNotificationsWeb.Endpoint,
<<<<<<< Updated upstream
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4002"))],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_please_change_in_production"
=======
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT", "4002"))
  ],
  url: [
    host: System.get_env("PHX_HOST", "localhost"),
    port: 4002
  ],
  secret_key_base: System.get_env("SECRET_KEY_BASE", "dev-secret-key-base-dev-secret-key-base-dev-secret-key-base"),
  check_origin: false,
  server: true
>>>>>>> Stashed changes
