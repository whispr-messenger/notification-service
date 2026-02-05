defmodule WhisprNotifications.Delivery.BatchProcessor do
  @moduledoc """
  Envoi batch des notifications sur un ensemble de devices.
  """

  alias WhisprNotifications.Devices.DeviceCache
  alias WhisprNotifications.Notifications.{Notification, Formatter}
  alias WhisprNotifications.Delivery.{FcmClient, ApnsClient, RetryManager}

  @spec deliver(Notification.t(), DeviceCache.t()) :: :ok
  def deliver(%Notification{} = notif, %DeviceCache{devices: devices}) do
    Enum.each(devices, fn device ->
      payload = Formatter.to_platform_payload(notif, device.platform)
      send_to_device(device.platform, device, payload, %{retries: 0, device: device, payload: payload, platform: device.platform})
    end)

    :ok
  end

defp send_to_device(:android, device, payload, _attempt) do
  FcmClient.send(device, payload)
  :ok
end

defp send_to_device(:ios, device, payload, _attempt) do
  ApnsClient.send(device, payload)
  :ok
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
end
