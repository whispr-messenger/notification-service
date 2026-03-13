defmodule WhisprNotifications.Delivery.PushDispatcher do
  @moduledoc """
  Orchestrates sending push notifications to all of a user's registered devices.
  Checks user preferences and conversation mutes before dispatching.
  """

  require Logger

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Delivery.FcmClient
  alias WhisprNotifications.Preferences.Settings
  alias WhisprNotifications.Notifications.Formatter

  @notification_types %{
    new_message: :new_message,
    group_invite: :group_invite,
    contact_request: :contact_request
  }

  @doc """
  Dispatches a push notification to all active devices for the given user.
  Respects user notification settings and conversation mutes.

  Options:
    - type: :new_message | :group_invite | :contact_request
    - conversation_id: optional, used for mute checking
  """
  def dispatch(user_id, title, body, data \\ %{}, opts \\ []) do
    type = Keyword.get(opts, :type, :new_message)
    conversation_id = Keyword.get(opts, :conversation_id)

    with :ok <- check_user_settings(user_id, type),
         :ok <- check_conversation_mute(user_id, conversation_id) do
      devices = Devices.list_user_devices(user_id)

      if Enum.empty?(devices) do
        Logger.debug("No active devices for user #{user_id}, skipping push")
        :ok
      else
        send_to_devices(devices, title, body, data)
      end
    else
      {:skip, reason} ->
        Logger.debug("Skipping notification for user #{user_id}: #{reason}")
        :ok
    end
  end

  defp check_user_settings(user_id, type) do
    if Settings.notification_enabled?(user_id, type) do
      :ok
    else
      {:skip, "notification type #{type} disabled"}
    end
  end

  defp check_conversation_mute(_user_id, nil), do: :ok

  defp check_conversation_mute(user_id, conversation_id) do
    if Settings.conversation_muted?(user_id, conversation_id) do
      {:skip, "conversation #{conversation_id} muted"}
    else
      :ok
    end
  end

  defp send_to_devices(devices, title, body, data) do
    results =
      Enum.map(devices, fn device ->
        case FcmClient.send_platform_message(device.token, device.platform, title, body, data) do
          :ok ->
            {:ok, device.device_id}

          {:error, :token_not_registered} ->
            Logger.info("Deactivating unregistered device token for device #{device.device_id}")
            Devices.deactivate_device(device.token)
            {:error, device.device_id, :token_not_registered}

          {:error, reason} ->
            Logger.warning("Failed to send push to device #{device.device_id}: #{inspect(reason)}")
            {:error, device.device_id, reason}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(errors) do
      :ok
    else
      {:partial, length(results) - length(errors), length(errors)}
    end
  end
end
