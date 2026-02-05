defmodule WhisprNotifications.Preferences.Manager do
  @moduledoc """
  API pour gérer et lire les préférences de notifications.
  Ici on encapsule l'accès au stockage (Repo, gRPC, etc.).
  """

  alias WhisprNotifications.Preferences.{UserSettings, ConversationSettings}
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
    # à remplacer par un vrai storage (Repo, cache, external service, etc.)
    {:ok, %UserSettings{user_id: user_id}}
  end

  @impl true
  def get_conversation_settings(user_id, conversation_id) do
    {:ok, %ConversationSettings{user_id: user_id, conversation_id: conversation_id}}
  end

  @spec allowed_for_notification?(Notification.t(), DateTime.t()) :: boolean()
  def allowed_for_notification?(%Notification{} = notif, now \\ DateTime.utc_now()) do
    with {:ok, user_settings} <- get_user_settings(notif.user_id),
         {:ok, conv_settings} <- get_conversation_settings(notif.user_id, notif.conversation_id) do
      not UserSettings.quiet_now?(user_settings, now) and
        not ConversationSettings.muted_now?(conv_settings, now)
    else
      _ -> true
    end
  end
end
