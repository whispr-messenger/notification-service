defmodule WhisprNotifications.Delivery.BatchProcessor do
  @moduledoc """
  Envoi batch des notifications sur un ensemble de devices.
  Les clients APNS/FCM concrets sont injectables via la config applicative
  (`:apns_client_mod`, `:fcm_client_mod`) pour faciliter les tests.
  """

  alias WhisprNotifications.Badges
  alias WhisprNotifications.Devices.DeviceCache
  alias WhisprNotifications.Notifications.{Notification, Formatter}
  alias WhisprNotifications.Delivery.{FcmClient, ApnsClient, RetryManager}

  @spec deliver(Notification.t(), DeviceCache.t()) :: :ok
  def deliver(%Notification{} = notif, %DeviceCache{devices: devices}) do
    badge = current_badge(notif.user_id)

    Enum.each(devices, fn device ->
      payload = Formatter.to_platform_payload(notif, device.platform, badge)

      attempt = %{
        retries: 0,
        device: device,
        payload: payload,
        platform: device.platform
      }

      send_to_device(device.platform, device, payload, attempt)
    end)

    :ok
  end

  defp send_to_device(:android, device, payload, attempt) do
    case fcm_client().send(device, payload) do
      :ok -> :ok
      {:error, _} -> maybe_retry(attempt)
    end
  end

  defp send_to_device(:ios, device, payload, attempt) do
    case apns_client().send(device, payload) do
      :ok -> :ok
      {:error, _} -> maybe_retry(attempt)
    end
  end

  defp send_to_device(:web, _device, _payload, _attempt), do: :ok

  defp maybe_retry(attempt) do
    if RetryManager.should_retry?(attempt) do
      attempt = RetryManager.next_attempt(attempt)
      send_to_device(attempt.platform, attempt.device, attempt.payload, attempt)
    else
      :ok
    end
  end

  defp apns_client do
    Application.get_env(:whispr_notification, :apns_client_mod, ApnsClient)
  end

  defp fcm_client do
    Application.get_env(:whispr_notification, :fcm_client_mod, FcmClient)
  end

  defp current_badge(nil), do: nil

  defp current_badge(user_id) when is_binary(user_id) do
    Badges.get(user_id)
  rescue
    _ -> nil
  end
end
