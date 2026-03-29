import Config

# Do not start the HTTP server in tests — the Phoenix Endpoint is still in the
# supervision tree (needed for PubSub routing) but should not bind a port.
config :whispr_notification, WhisprNotificationsWeb.Endpoint,
  server: false
