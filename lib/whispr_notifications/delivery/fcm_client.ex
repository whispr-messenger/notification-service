defmodule WhisprNotifications.Delivery.FcmClient do
  @moduledoc """
  Client FCM pour envoyer les notifications vers Android ou IOS via FCM
  """

  alias WhisprNotifications.Devices.DeviceCache
  @callback send(DeviceCache.device(), map()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def send(_device, _payload) do
    # Par défaut, ne fait rien.
    # À implémenter avec Pigeon, HTTP direct, ou autre [web:12][web:15].
    :ok
  end
end
