defmodule WhisprNotifications.Delivery.ApnsClient do
  @moduledoc """
  Client APNS pour envoyer les notifications vers iOS.
  La fonction d'envoi réelle peut être injectée via la config applicative
  `:apns_push_fun` (utile pour tester sans toucher Apple).
  """

  require Logger

  alias WhisprNotifications.Devices.DeviceCache

  @callback send(DeviceCache.device(), map()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  @spec send(DeviceCache.device(), map()) :: :ok | {:error, term()}
  def send(device, payload) do
    push_fun = Application.get_env(:whispr_notification, :apns_push_fun, &default_push/2)

    case push_fun.(device, payload) do
      :ok ->
        Logger.info("APNS push succeeded for #{masked_token(device)}")
        :ok

      {:error, reason} = err ->
        Logger.error("APNS push failed for #{masked_token(device)}: #{inspect(reason)}")
        err
    end
  end

  defp default_push(_device, _payload), do: :ok

  defp masked_token(device) do
    case token(device) do
      "unknown" ->
        "unknown"

      t when is_binary(t) ->
        suffix_length = min(String.length(t), 6)
        "***" <> String.slice(t, -suffix_length, suffix_length)
    end
  end

  defp token(%{token: t}) when is_binary(t), do: t
  defp token(_), do: "unknown"
end
