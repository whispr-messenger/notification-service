defmodule WhisprNotifications.Delivery.BatchProcessor do
  @moduledoc """
  Envoi batch des notifications sur un ensemble de devices.
  """

  alias WhisprNotifications.Delivery.RetryManager
  alias WhisprNotifications.Devices.DeviceCache
  alias WhisprNotifications.Notifications.{Formatter, Notification}

  @spec deliver(Notification.t(), DeviceCache.t()) :: :ok
  def deliver(%Notification{} = notif, %DeviceCache{devices: devices}) do
    Enum.each(devices, fn device ->
      payload = Formatter.to_platform_payload(notif, device.platform)

      send_to_device(device.platform, device, payload, %{
        retries: 0,
        device: device,
        payload: payload,
        platform: device.platform
      })
    end)

    :ok
  end

  defp send_to_device(:android, device, payload, _attempt) do
    fcm_client().send(device, payload)
    :ok
  end

  defp send_to_device(:ios, device, payload, attempt) do
    case apns_client().send(device, payload) do
      :ok -> :ok
      {:error, _reason} -> maybe_retry(attempt)
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
    Application.get_env(
      :whispr_notification,
      :apns_client_mod,
      WhisprNotifications.Delivery.ApnsClient
    )
  end

  defp fcm_client do
    Application.get_env(
      :whispr_notification,
      :fcm_client_mod,
      WhisprNotifications.Delivery.FcmClient
    )
  end
end
