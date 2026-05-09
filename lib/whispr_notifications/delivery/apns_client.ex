defmodule WhisprNotifications.Delivery.ApnsClient do
  @moduledoc """
  Push APNS via Pigeon 2.x (HTTP/2 + JWT ES256).

  Meme contrat de callback que le stub precedent pour eviter d'avoir a
  toucher `BatchProcessor` ni `Devices.mark_invalid/2` :

      :ok
      | {:error, :token_invalid}     # echec definitif, soft-delete le device
      | {:error, :transient}         # retryable (reseau, 5xx, quota, auth)
      | {:error, :not_configured}    # creds APNS absents (dev/CI)

  Mapping des atomes de reponse de `Pigeon.APNS` :

    * `:success`                                          -> `:ok`
    * `:bad_device_token`, `:unregistered`,
      `:device_token_not_for_topic`, `:missing_device_token`,
      `:expired_token`, `:bad_topic`, `:topic_disallowed`,
      `:invalid_push_type`                                -> `{:error, :token_invalid}`
    * `:internal_server_error`, `:service_unavailable`,
      `:too_many_requests`, `:too_many_provider_token_updates`,
      `:expired_provider_token`, `:invalid_provider_token`,
      `:missing_provider_token`, `:idle_timeout`,
      `:shutdown`, `:unknown_error`, `:timeout`           -> `{:error, :transient}`

  Tout le reste retombe sur `:transient` pour eviter de perdre un token
  valide sur une erreur qu'on n'avait pas prevue.
  """

  alias Pigeon.APNS.Notification, as: APNSNotification
  alias WhisprNotifications.Delivery.ApnsDispatcher
  alias WhisprNotifications.Devices.DeviceCache

  require Logger

  @callback send(DeviceCache.device(), map()) ::
              :ok | {:error, :token_invalid | :transient | :not_configured | term()}

  @behaviour __MODULE__

  @invalid_token_responses [
    :bad_device_token,
    :unregistered,
    :device_token_not_for_topic,
    :missing_device_token,
    :expired_token,
    :bad_topic,
    :topic_disallowed,
    :invalid_push_type
  ]

  @impl true
  @spec send(DeviceCache.device(), map()) ::
          :ok | {:error, :token_invalid | :transient | :not_configured | term()}
  def send(%{token: token} = device, payload)
      when is_binary(token) and token != "" do
    cond do
      not apns_enabled?() -> {:error, :not_configured}
      not dispatcher_running?() -> {:error, :not_configured}
      true -> do_push(device, payload)
    end
  end

  def send(_device, _payload), do: {:error, :token_invalid}

  @doc """
  Construit une `Pigeon.APNS.Notification` a partir de la shape payload
  interne utilisee par `BatchProcessor` +
  `Formatter.to_platform_payload/3`. Public pour pouvoir etre teste
  sans avoir a demarrer un dispatcher.
  """
  @spec build_notification(DeviceCache.device(), map()) :: APNSNotification.t()
  def build_notification(%{token: token} = device, payload) do
    topic = topic_for(device)

    %APNSNotification{
      device_token: token,
      topic: topic,
      push_type: "alert",
      # collapse_id : APNs deduplique sur cette cle si on rejoue un push
      # apres une race :DOWN cote subscriber Redis. derive de l'id de notif
      # via le Formatter (Pigeon impose 64 octets max, on est tres en dessous).
      collapse_id: collapse_id(payload),
      payload: normalise_payload(payload)
    }
  end

  @doc """
  Mapping pur d'un atome de reponse Pigeon APNS vers le contrat interne
  `ApnsClient`. Public pour les tests unitaires.
  """
  @spec response_to_result(APNSNotification.t()) ::
          :ok | {:error, :token_invalid | :transient}
  def response_to_result(%APNSNotification{response: :success}), do: :ok

  def response_to_result(%APNSNotification{response: resp})
      when resp in @invalid_token_responses do
    {:error, :token_invalid}
  end

  def response_to_result(%APNSNotification{response: resp}) do
    Logger.warning("[ApnsClient] transient APNS response: #{inspect(resp)}")
    {:error, :transient}
  end

  # ----- prive ----------------------------------------------------------

  defp apns_enabled? do
    :whispr_notification
    |> Application.get_env(:apns, [])
    |> Keyword.get(:enabled, false) == true
  end

  defp dispatcher_running? do
    dispatcher_module() |> Process.whereis() != nil
  end

  defp dispatcher_module do
    Application.get_env(:whispr_notification, :apns_dispatcher, ApnsDispatcher)
  end

  defp do_push(device, payload) do
    notification = build_notification(device, payload)
    dispatcher = dispatcher_module()
    masked = masked_token(device)

    case dispatcher.push(notification) |> response_to_result() do
      :ok ->
        Logger.info("APNS push succeeded for #{masked}")
        :ok

      {:error, reason} = err ->
        Logger.error("APNS push failed for #{masked}: #{inspect(reason)}")
        err
    end
  rescue
    e ->
      Logger.warning("[ApnsClient] Pigeon push raised: #{inspect(e)}")
      {:error, :transient}
  catch
    :exit, _ -> {:error, :not_configured}
  end

  # le topic APNS = le bundle id de l'app. fallback sur un default
  # configure si le device en DB n'en porte pas (anciens inserts avant
  # l'ajout de la colonne).
  defp topic_for(%{app: app}) when is_binary(app) and app != "", do: app

  defp topic_for(_device) do
    :whispr_notification
    |> Application.get_env(:apns, [])
    |> Keyword.get(:default_topic)
  end

  # accepte la shape `Formatter.to_platform_payload/3` (deja
  # `%{"aps" => %{...}, "meta" => %{...}}`) et une shape plate
  # `%{title, body}` utilisee par certains callers/tests.
  # collapse_id est extrait separement (transport via header APNs), on le
  # retire du body JSON pour eviter du bruit cote payload Apple.
  defp normalise_payload(%{"aps" => _} = payload),
    do: Map.drop(payload, ["collapse_id", :collapse_id])

  defp normalise_payload(%{title: title, body: body} = payload) do
    base = %{
      "aps" => %{
        "alert" => %{
          "title" => to_string(title),
          "body" => to_string(body)
        },
        "sound" => "default"
      }
    }

    case Map.get(payload, :data) do
      map when is_map(map) and map_size(map) > 0 ->
        Map.put(base, "meta", Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end))

      _ ->
        base
    end
  end

  defp normalise_payload(payload) when is_map(payload), do: payload

  defp masked_token(device) do
    case token(device) do
      # coveralls-ignore-start
      "unknown" ->
        "unknown"

      # coveralls-ignore-stop
      t when is_binary(t) ->
        suffix_length = min(String.length(t), 6)
        "***" <> String.slice(t, -suffix_length, suffix_length)
    end
  end

  defp token(%{token: t}) when is_binary(t), do: t
  # coveralls-ignore-start
  defp token(_), do: "unknown"
  # coveralls-ignore-stop

  # le Formatter pose la cle sous "collapse_id" (string), mais on tolere aussi
  # une shape avec atom : utile pour les tests qui passent un payload plat.
  defp collapse_id(payload) when is_map(payload) do
    case Map.get(payload, "collapse_id") || Map.get(payload, :collapse_id) do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  # coveralls-ignore-next-line - defensive non-map fallback
  defp collapse_id(_), do: nil
end
