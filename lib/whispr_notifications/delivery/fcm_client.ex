defmodule WhisprNotifications.Delivery.FcmClient do
  @moduledoc """
  FCM push via Pigeon 2.x (HTTP v1 + OAuth Goth).

  Keeps the same callback contract as the previous custom HTTP client so
  `BatchProcessor` and `Devices.mark_invalid/2` don't need to change:

      :ok
      | {:error, :token_invalid}     # hard failure — soft-delete the device
      | {:error, :transient}         # retryable (network, 5xx, quota, auth)
      | {:error, :not_configured}    # FCM creds absent in this env (dev/CI)

  Response atoms from `Pigeon.FCM` are mapped as follows:

    * `:success`                                         → `:ok`
    * `:unregistered`, `:invalid_argument`,
      `:sender_id_mismatch`                              → `{:error, :token_invalid}`
    * `:permission_denied`, `:third_party_auth_error`,
      `:quota_exceeded`, `:unavailable`, `:internal`,
      `:unspecified_error`, `:unknown_error`             → `{:error, :transient}`

  Everything unknown degrades to `:transient` so we never drop a valid token
  on an error we didn't anticipate.
  """

  alias Pigeon.FCM.Notification, as: FCMNotification
  alias WhisprNotifications.Delivery.FcmDispatcher
  alias WhisprNotifications.Devices.DeviceCache

  require Logger

  @callback send(DeviceCache.device(), map()) ::
              :ok | {:error, :token_invalid | :transient | :not_configured | term()}

  @behaviour __MODULE__

  @invalid_token_responses [:unregistered, :invalid_argument, :sender_id_mismatch]

  @impl true
  def send(%{token: token, platform: platform}, payload)
      when is_binary(token) and token != "" do
    cond do
      not fcm_enabled?() -> {:error, :not_configured}
      not dispatcher_running?() -> {:error, :not_configured}
      true -> do_push(token, platform, payload)
    end
  end

  def send(_device, _payload), do: {:error, :token_invalid}

  @doc """
  Builds a `Pigeon.FCM.Notification` from the internal payload shape used by
  `BatchProcessor` + `Formatter`. Public so it can be unit-tested without
  standing up a dispatcher.
  """
  @spec build_notification(String.t(), atom(), map()) :: FCMNotification.t()
  def build_notification(token, platform, payload) do
    {:token, token}
    |> FCMNotification.new(notification_map(payload), data_map(payload))
    |> put_android(platform)
  end

  @doc """
  Pure mapping from a Pigeon FCM response atom back to the internal
  `FcmClient` contract. Public for unit-testing.
  """
  @spec response_to_result(FCMNotification.t()) ::
          :ok | {:error, :token_invalid | :transient}
  def response_to_result(%FCMNotification{response: :success}), do: :ok

  def response_to_result(%FCMNotification{response: resp})
      when resp in @invalid_token_responses do
    {:error, :token_invalid}
  end

  def response_to_result(%FCMNotification{response: resp}) do
    Logger.warning("[FcmClient] transient FCM response: #{inspect(resp)}")
    {:error, :transient}
  end

  # ----- private ---------------------------------------------------------

  defp fcm_enabled? do
    :whispr_notification
    |> Application.get_env(:fcm, [])
    |> Keyword.get(:enabled, false) == true
  end

  defp dispatcher_running? do
    dispatcher_module() |> Process.whereis() != nil
  end

  defp dispatcher_module do
    Application.get_env(:whispr_notification, :fcm_dispatcher, FcmDispatcher)
  end

  defp do_push(token, platform, payload) do
    notification = build_notification(token, platform, payload)
    dispatcher = dispatcher_module()

    dispatcher.push(notification) |> response_to_result()
  rescue
    e ->
      Logger.warning("[FcmClient] Pigeon push raised: #{inspect(e)}")
      {:error, :transient}
  catch
    :exit, _ -> {:error, :not_configured}
  end

  # Accepts both a flat shape (`%{title, body, data}`) and the
  # `Formatter.to_platform_payload/3` shape
  # (`%{notification: %{title, body}, data: ...}`). The latter is what
  # BatchProcessor actually passes in.
  defp notification_map(payload) do
    nested = Map.get(payload, :notification) || %{}

    %{
      "title" => to_string(Map.get(payload, :title) || Map.get(nested, :title, "")),
      "body" => to_string(Map.get(payload, :body) || Map.get(nested, :body, ""))
    }
  end

  defp data_map(payload) do
    case Map.get(payload, :data) do
      map when is_map(map) and map_size(map) > 0 ->
        Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)

      _ ->
        nil
    end
  end

  # Android `priority: HIGH` matches the behaviour of the old custom client:
  # notifications delivered immediately even if the device is dozing.
  defp put_android(%FCMNotification{} = notif, :android),
    do: %{notif | android: %{"priority" => "HIGH"}}

  defp put_android(%FCMNotification{} = notif, _), do: notif
end
