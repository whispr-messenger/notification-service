defmodule WhisprNotifications.Delivery.ApnsClient do
  @moduledoc """
  Client APNS pour envoyer les notifications vers iOS.
  """

  alias WhisprNotifications.Devices.DeviceCache

  @callback send(DeviceCache.device(), map()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def send(device, payload) do
    # À implémenter via Pigeon ou un service externe type MongoosePush [web:6][web:12].
    _ = {device, payload}
    :ok
  end
end
