defmodule WhisprNotifications.Delivery.ApnsClient do
  @moduledoc """
  Client APNS pour envoyer les notifications vers iOS.
  """

  require Logger

  alias WhisprNotifications.Devices.DeviceCache

  @callback send(DeviceCache.device(), map()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def send(device, payload) do
    push_fun = Application.get_env(:whispr_notification, :apns_push_fun, &default_push/2)

    case push_fun.(device, payload) do
      :ok ->
        Logger.info("APNS push succeeded for #{device.token}")
        :ok

      {:error, reason} = err ->
        Logger.error(
          "APNS push failed for #{device.token}: #{inspect(reason)}"
        )

        err
    end
  end

  defp default_push(_device, _payload) do
    # À implémenter via Pigeon ou un service externe type MongoosePush.
    :ok
  end
end
