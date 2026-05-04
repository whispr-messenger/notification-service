import Config

# Kubernetes service discovery may inject full URIs (e.g. "tcp://10.x.x.x:6379")
# into *_PORT variables instead of plain port numbers. This helper handles both.
parse_port = fn value ->
  case URI.parse(value) do
    %URI{port: port} when is_integer(port) -> port
    _ -> String.to_integer(value)
  end
end

# ======================================================================
# Redis (tous environnements — dev / test / prod)
# Lecture au démarrage du release. Mode `direct` (par défaut) ou `sentinel`
# (HA) sélectionné via REDIS_MODE. La construction des opts Redix se fait
# via WhisprNotifications.RedisConfig.build/0.
# ======================================================================

redis_mode = System.get_env("REDIS_MODE", "direct")

redis_config =
  case redis_mode do
    "sentinel" ->
      [
        mode: "sentinel",
        sentinels: System.get_env("REDIS_SENTINELS"),
        master_name: System.get_env("REDIS_MASTER_NAME"),
        sentinel_password: System.get_env("REDIS_SENTINEL_PASSWORD"),
        database:
          String.to_integer(
            System.get_env("REDIS_DB", if(config_env() == :test, do: "1", else: "0"))
          ),
        username: System.get_env("REDIS_USERNAME"),
        password: System.get_env("REDIS_PASSWORD"),
        timeout: 15_000,
        ssl: System.get_env("REDIS_SSL", "false") == "true"
      ]

    _ ->
      [
        mode: "direct",
        host: System.get_env("REDIS_HOST", "localhost"),
        port: parse_port.(System.get_env("REDIS_PORT", "6379")),
        database:
          String.to_integer(
            System.get_env("REDIS_DB", if(config_env() == :test, do: "1", else: "0"))
          ),
        username: System.get_env("REDIS_USERNAME"),
        password: System.get_env("REDIS_PASSWORD"),
        timeout: 15_000,
        ssl: System.get_env("REDIS_SSL", "false") == "true"
      ]
  end

config :whispr_notification, :redis, redis_config

# ======================================================================
# JWT / JWKS (tous environnements — dev / test / prod)
# Chargement dynamique des clés publiques depuis l'endpoint JWKS de l'auth-service.
# ======================================================================

config :whispr_notification, :jwt,
  jwks_url:
    System.get_env(
      "AUTH_JWKS_URL",
      "http://auth-service/auth/.well-known/jwks.json"
    ),
  refresh_interval_ms: String.to_integer(System.get_env("JWKS_REFRESH_INTERVAL_MS", "3600000")),
  allowed_algs: ["ES256"],
  issuer: System.get_env("JWT_ISSUER"),
  audience: System.get_env("JWT_AUDIENCE")

# ======================================================================
# Production-only configuration
# ======================================================================

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Example: ecto://USER:PASS@HOST/DATABASE
      """

  config :whispr_notification, WhisprNotifications.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10")),
    ssl: System.get_env("DATABASE_SSL", "false") == "true"

  config :whispr_notification, WhisprNotificationsWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "4011"))
    ],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    url: [
      host: System.get_env("PHX_HOST", "localhost"),
      port: 443,
      scheme: "https"
    ],
    check_origin: false,
    server: true

  config :whispr_notification,
    grpc_port: String.to_integer(System.get_env("GRPC_PORT", "40011"))
end

# WHISPR-1068 : LOG_FORMAT=json → formatter JSON unifié avec les services
# NestJS. Sinon on garde la sortie texte native pour `mix phx.server`.
if System.get_env("LOG_FORMAT") == "json" do
  config :logger, :console,
    format: {WhisprNotifications.JsonFormatter, :format},
    metadata: :all
end

# WHISPR-1157 : FCM HTTP v1. Le service account JSON arrive soit via le
# chemin d'un fichier (FCM_JSON_KEYFILE) soit en ligne (FCM_JSON). Quand
# aucun n'est positionné (dev sans creds) le dispatcher ne démarre pas
# Goth et FcmClient renvoie {:error, :not_configured}.
fcm_project_id = System.get_env("FCM_PROJECT_ID")

fcm_credentials =
  cond do
    json = System.get_env("FCM_JSON") ->
      case Jason.decode(json) do
        {:ok, decoded} -> decoded
        _ -> nil
      end

    path = System.get_env("FCM_JSON_KEYFILE") ->
      case File.read(path) do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, decoded} -> decoded
            _ -> nil
          end

        _ ->
          nil
      end

    true ->
      nil
  end

config :whispr_notification, :fcm,
  project_id: fcm_project_id,
  credentials: fcm_credentials,
  enabled: is_binary(fcm_project_id) and fcm_project_id != "" and is_map(fcm_credentials)

# Pigeon.FCM dispatcher config. Only meaningful when the dispatcher is
# actually started (cf. WhisprNotifications.Application.fcm_children/0), but
# we set it unconditionally so `use Pigeon.Dispatcher` finds its config at
# compile-time introspection and `Process.whereis/1` remains the single
# source of truth for "is FCM available".
if is_binary(fcm_project_id) and fcm_project_id != "" do
  config :whispr_notification, WhisprNotifications.Delivery.FcmDispatcher,
    adapter: Pigeon.FCM,
    auth: WhisprNotifications.Goth,
    project_id: fcm_project_id
end

# WHISPR-1176 : APNS HTTP/2 + JWT ES256 via Pigeon. The dispatcher is only
# added to the supervision tree by `WhisprNotifications.Application` when
# `enabled` below is `true`. The `:apns` keyword is the source of truth for
# `ApnsClient.send/2`'s `{:error, :not_configured}` short-circuit. Never
# log the .p8 contents.
apns_key_path = System.get_env("APNS_KEY_PATH")
apns_key_id = System.get_env("APNS_KEY_ID")
apns_team_id = System.get_env("APNS_TEAM_ID")

apns_mode =
  case System.get_env("APNS_MODE") do
    "prod" -> :prod
    _ -> :dev
  end

apns_default_topic = System.get_env("APNS_DEFAULT_TOPIC")

apns_enabled? =
  is_binary(apns_key_path) and apns_key_path != "" and
    is_binary(apns_key_id) and apns_key_id != "" and
    is_binary(apns_team_id) and apns_team_id != ""

config :whispr_notification, :apns,
  enabled: apns_enabled?,
  key_path: apns_key_path,
  key_id: apns_key_id,
  team_id: apns_team_id,
  mode: apns_mode,
  default_topic: apns_default_topic

if apns_enabled? do
  config :whispr_notification, WhisprNotifications.Delivery.ApnsDispatcher,
    adapter: Pigeon.APNS,
    key: apns_key_path,
    key_identifier: apns_key_id,
    team_id: apns_team_id,
    mode: apns_mode
end
