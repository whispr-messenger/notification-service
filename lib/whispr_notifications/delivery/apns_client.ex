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
    with {:ok, topic} <- fetch_topic(),
         {:ok, token} <- fetch_token(device) do
      notification =
        Pigeon.APNS.Notification.new(
          normalize_payload(payload),
          token,
          topic
        )

      case WhisprNotifications.APNS.push(notification) do
        %Pigeon.APNS.Notification{response: :success} ->
          Logger.info("APNS push sent successfully")
          :ok

        %Pigeon.APNS.Notification{response: {:error, reason}} ->
          Logger.warning("APNS push failed: #{inspect(reason)}")
          {:error, {:apns_error, reason}}

        other ->
          Logger.warning("Unexpected APNS response: #{inspect(other)}")
          {:error, :unexpected_apns_response}
      end
    else
      {:error, reason} ->
        Logger.warning("APNS push skipped: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_topic do
    topic =
      Application.get_env(:whispr_notification, WhisprNotifications.APNS, [])
      |> Keyword.get(:topic)

    if is_binary(topic) and topic != "" do
      {:ok, topic}
    else
      {:error, :apns_topic_not_configured}
    end
  end

  defp fetch_token(%{token: token}) when is_binary(token) and token != "", do: {:ok, token}
  defp fetch_token(_), do: {:error, :invalid_device_token}

  defp normalize_payload(%{"aps" => _} = payload), do: payload

  defp normalize_payload(payload) when is_map(payload) do
    title = get_in(payload, [:notification, :title]) || get_in(payload, ["notification", "title"])
    body = get_in(payload, [:notification, :body]) || get_in(payload, ["notification", "body"])

    aps_alert =
      case {title, body} do
        {nil, nil} -> %{}
        {t, nil} -> %{"title" => to_string(t)}
        {nil, b} -> %{"body" => to_string(b)}
        {t, b} -> %{"title" => to_string(t), "body" => to_string(b)}
      end

    data =
      payload
      |> Map.get(:data, %{})
      |> stringify_map()

    %{
      "aps" => %{
        "alert" => aps_alert,
        "sound" => "default"
      },
      "data" => data
    }
  end

  defp normalize_payload(_), do: %{"aps" => %{"sound" => "default"}}

  defp stringify_map(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_map(_), do: %{}
end
