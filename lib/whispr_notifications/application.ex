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
        # Repo Ecto, doit demarrer avant tout ce qui requete la DB
        WhisprNotifications.Repo,
        # PubSub, doit demarrer avant l'Endpoint
        {Phoenix.PubSub, name: WhisprNotifications.PubSub},
        # cache JWKS : doit demarrer avant l'Endpoint pour que le plug
        # Authenticate ait un GenServer pret des la 1ere requete
        {WhisprNotifications.Auth.JwksCache, jwks_cache_opts()},
        # endpoint HTTP Phoenix, bind le port HTTP declare dans la config
        WhisprNotificationsWeb.Endpoint,
        # superviseurs et workers du domaine
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

  # les dispatchers push (Pigeon FCM + Pigeon APNS) ne demarrent que si
  # leurs creds respectifs sont fournis. sinon on laisse l'arbre booter
  # proprement en dev/CI et le client retourne `{:error, :not_configured}`.
  defp push_children do
    fcm_children() ++ apns_children()
  end

  # dispatcher Goth + Pigeon FCM, requiert service account FCM + project id
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
        Logger.info("[FCM] non configure - Goth + FcmDispatcher non demarres")
        []
    end
  end

  # dispatcher Pigeon APNS, requiert chemin du .p8 + key id + team id
  @doc false
  def apns_children do
    cfg = Application.get_env(:whispr_notification, :apns, [])

    if Keyword.get(cfg, :enabled, false) do
      [WhisprNotifications.Delivery.ApnsDispatcher]
    else
      Logger.info("[APNS] non configure - ApnsDispatcher non demarre")
      []
    end
  end

  # requis par Phoenix pour recharger la conf via config_change/3
  @impl true
  def config_change(changed, _new, removed) do
    WhisprNotificationsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # construit les options du JwksCache. on prefetch les JWKS une fois au
  # boot pour que le cache demarre avec des cles reelles. si auth-service
  # est injoignable, on tombe sur un key set vide pour que l'app demarre
  # quand meme (le plug renverra juste 401 jusqu'au prochain refresh) au
  # lieu de crash-looper le superviseur.
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
          "JWKS prefetch from #{inspect(url)} failed: #{inspect(reason)} - starting with empty key set"
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
