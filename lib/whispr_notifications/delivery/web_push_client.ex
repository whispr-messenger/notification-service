defmodule WhisprNotifications.Delivery.WebPushClient do
  @moduledoc """
  Web Push VAPID pour iOS PWA Safari (et navigateurs W3C Web Push).

  Contrat de callback identique aux autres clients de livraison :

      :ok
      | {:error, :endpoint_expired}   # 410 Gone / 404 — soft-delete le device
      | {:error, :not_configured}     # clés VAPID absentes (dev/CI)
      | {:error, :transient}          # réseau, 5xx — retryable

  Le champ `device.token` contient l'endpoint Web Push.
  Les champs `device.wp_p256dh` et `device.wp_auth` contiennent les clés
  de chiffrement du navigateur.

  Utilise `WebPushElixir.send_notification/3` qui attend une subscription
  au format JSON : `{"endpoint": "...", "keys": {"p256dh": "...", "auth": "..."}}`.
  """

  alias WhisprNotifications.Devices.DeviceCache

  require Logger

  @callback send(DeviceCache.device(), map()) ::
              :ok | {:error, :endpoint_expired | :not_configured | :transient | term()}

  @behaviour __MODULE__

  @impl true
  def send(%{token: endpoint, platform: :web_push, wp_p256dh: p256dh, wp_auth: auth}, payload)
      when is_binary(endpoint) and endpoint != "" and
             is_binary(p256dh) and is_binary(auth) do
    if vapid_configured?() do
      subscription_json = build_subscription_json(endpoint, p256dh, auth)
      message = encode_payload(payload)
      do_push(subscription_json, message, endpoint)
    else
      {:error, :not_configured}
    end
  end

  def send(_device, _payload), do: {:error, :not_configured}

  # ----- privé -----------------------------------------------------------

  defp vapid_configured? do
    pub = Application.get_env(:web_push_elixir, :vapid_public_key, "")
    priv = Application.get_env(:web_push_elixir, :vapid_private_key, "")
    is_binary(pub) and pub != "" and is_binary(priv) and priv != ""
  end

  # web_push_elixir attend une subscription au format JSON (string)
  defp build_subscription_json(endpoint, p256dh, auth) do
    Jason.encode!(%{
      "endpoint" => endpoint,
      "keys" => %{
        "p256dh" => p256dh,
        "auth" => auth
      }
    })
  end

  defp encode_payload(payload) do
    title = get_in(payload, [:notification, :title]) || Map.get(payload, :title, "")
    body = get_in(payload, [:notification, :body]) || Map.get(payload, :body, "")
    data = Map.get(payload, :data, %{})

    Jason.encode!(%{
      notification: %{
        title: to_string(title),
        body: to_string(body)
      },
      data: data
    })
  end

  # coveralls-ignore-start — appels réseau réels via WebPushElixir, non exercés en CI sans serveur VAPID
  defp do_push(subscription_json, message, endpoint) do
    case WebPushElixir.send_notification(subscription_json, message) do
      {:ok, _response} ->
        :ok

      {:error, :expired} ->
        Logger.info("[WebPushClient] endpoint expiré: #{endpoint}")
        {:error, :endpoint_expired}

      {:error, {:http_error, status, body}} ->
        Logger.warning("[WebPushClient] HTTP #{status} pour #{endpoint}: #{inspect(body)}")
        {:error, :transient}
    end
  rescue
    e ->
      Logger.warning("[WebPushClient] push a levé une exception: #{inspect(e)}")
      {:error, :transient}
  end
  # coveralls-ignore-stop
end
