defmodule WhisprNotifications.Application do
  @moduledoc """
  OTP application pour le domaine de notifications.
  Démarre les superviseurs nécessaires (PubSub, Endpoint HTTP, cache devices, workers, etc.).
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        # Ecto Repo — must start before anything that queries the DB
        WhisprNotifications.Repo,
        # PubSub — must start before the Endpoint
        {Phoenix.PubSub, name: WhisprNotifications.PubSub},
        # JWKS cache — must start before the Endpoint so the Authenticate plug
        # has a live GenServer to call on the very first request.
        {WhisprNotifications.Auth.JwksCache, jwks_cache_opts()},
        # Phoenix HTTP endpoint — binds the HTTP port declared in config
        WhisprNotificationsWeb.Endpoint,
        # Domain supervisors/workers
        {WhisprNotifications.Devices.CacheManager, []},
        {WhisprNotifications.Workers.TokenRefresher, []},
        {WhisprNotifications.Workers.CacheSyncWorker, []},
        {WhisprNotifications.Workers.CleanupWorker, []},
        {WhisprNotifications.Workers.MetricsWorker, []},
        {WhisprNotifications.Workers.ModerationSubscriber, []},
        {WhisprNotifications.Workers.CallsSubscriber, []},
        {WhisprNotifications.Workers.MessagingSubscriber, []},
        {WhisprNotifications.Workers.ContactsSubscriber, []}
      ] ++ push_children()

    opts = [strategy: :one_for_one, name: WhisprNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Push dispatchers (Pigeon FCM + Pigeon APNS) only start when their
  # respective creds are present. Otherwise we let the tree boot cleanly in
  # dev/CI and the matching client returns `{:error, :not_configured}`.
  defp push_children do
    fcm_children() ++ apns_children()
  end

  # Goth + Pigeon FCM dispatcher — needs FCM service account + project id.
  @doc false
  def fcm_children do
    cfg = Application.get_env(:whispr_notification, :fcm, [])

    with true <- Keyword.get(cfg, :enabled, false),
         credentials when is_map(credentials) <- Keyword.get(cfg, :credentials) do
      [
        {Goth, name: WhisprNotifications.Goth, source: {:service_account, credentials}},
        WhisprNotifications.Delivery.FcmDispatcher
      ]
    else
      _ ->
        Logger.info("[FCM] not configured — Goth + FcmDispatcher not started")
        []
    end
  end

  # Pigeon APNS dispatcher — needs the .p8 path + key id + team id.
  @doc false
  def apns_children do
    cfg = Application.get_env(:whispr_notification, :apns, [])

    if Keyword.get(cfg, :enabled, false) do
      [WhisprNotifications.Delivery.ApnsDispatcher]
    else
      Logger.info("[APNS] not configured — ApnsDispatcher not started")
      []
    end
  end

  # Required by Phoenix to reload configuration on config_change/3
  @impl true
  def config_change(changed, _new, removed) do
    WhisprNotificationsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Build JwksCache options. We pre-fetch the JWKS once at boot so the cache
  # starts with real keys; if the auth-service is unreachable, we fall back to
  # an empty key set so the app still starts (the plug will just return 401
  # until the cache is repopulated) instead of crash-looping the supervisor.
  @doc false
  def jwks_cache_opts do
    jwt_cfg = Application.get_env(:whispr_notification, :jwt, [])
    url = Keyword.get(jwt_cfg, :jwks_url)
    refresh_ms = Keyword.get(jwt_cfg, :refresh_interval_ms, 3_600_000)
    base = [refresh_interval_ms: refresh_ms]

    case prefetch_jwks(url) do
      {:ok, body} ->
        [{:inline_jwks, body}, {:jwks_url, url} | base]

      :unconfigured ->
        [{:allow_empty, true} | base]

      {:error, reason} ->
        Logger.warning(
          "JWKS prefetch from #{inspect(url)} failed: #{inspect(reason)} — starting with empty key set"
        )

        [{:allow_empty, true}, {:jwks_url, url} | base]
    end
  end

  @doc false
  def prefetch_jwks(url) when is_binary(url) and url != "" do
    case Req.get(url, receive_timeout: 5_000, retry: :transient, max_retries: 1) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, if(is_binary(body), do: body, else: Jason.encode!(body))}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end

    # coveralls-ignore-start
  rescue
    e ->
      {:error, e}
      # coveralls-ignore-stop
  end

  def prefetch_jwks(_), do: :unconfigured
end
