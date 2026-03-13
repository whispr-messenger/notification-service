defmodule WhisprNotifications.Preferences.Manager do
  @moduledoc """
  API for managing and reading notification preferences.
  Delegates to the database-backed Settings module and maintains
  backward compatibility with the in-memory structs.
  """

  alias WhisprNotifications.Preferences.{UserSettings, ConversationSettings, Settings}
  alias WhisprNotifications.Notifications.Notification

  defmodule Behaviour do
    @callback get_user_settings(String.t()) ::
                {:ok, UserSettings.t()} | {:error, term()}

    @callback get_conversation_settings(String.t(), String.t()) ::
                {:ok, ConversationSettings.t()} | {:error, term()}
  end

  @behaviour Behaviour

  @impl true
  def get_user_settings(user_id) do
    case Settings.get_user_settings(user_id) do
      {:ok, db_settings} ->
        {:ok, %UserSettings{
          user_id: user_id,
          message_push_enabled: db_settings.message_notifications,
          system_push_enabled: not db_settings.mute_all
        }}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def get_conversation_settings(user_id, conversation_id) do
    muted = Settings.conversation_muted?(user_id, conversation_id)
    {:ok, %ConversationSettings{
      user_id: user_id,
      conversation_id: conversation_id,
      muted: muted
    }}
  end

  @spec allowed_for_notification?(Notification.t(), DateTime.t()) :: boolean()
  def allowed_for_notification?(%Notification{} = notif, now \\ DateTime.utc_now()) do
    with {:ok, user_settings} <- get_user_settings(notif.user_id),
         {:ok, conv_settings} <- get_conversation_settings(notif.user_id, notif.conversation_id || "") do
      not UserSettings.quiet_now?(user_settings, now) and
        not ConversationSettings.muted_now?(conv_settings, now)
    else
      _ -> true
    end
  end
end
