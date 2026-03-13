defmodule WhisprNotifications.Preferences.Settings do
  @moduledoc """
  Context module for managing notification settings.
  Handles per-user notification preferences and per-conversation mutes.
  """

  import Ecto.Query
  alias WhisprNotifications.Repo
  alias WhisprNotifications.Preferences.{NotificationSetting, ConversationMute}

  # --- Notification Settings ---

  @doc """
  Returns the notification settings for a user.
  Creates default settings if none exist.
  """
  def get_user_settings(user_id) do
    case Repo.get_by(NotificationSetting, user_id: user_id) do
      nil -> create_default_settings(user_id)
      settings -> {:ok, settings}
    end
  end

  @doc """
  Updates notification settings for a user.
  Creates the record first if it doesn't exist.
  """
  def update_user_settings(user_id, attrs) do
    {:ok, settings} = get_user_settings(user_id)

    settings
    |> NotificationSetting.update_changeset(normalize_attrs(attrs))
    |> Repo.update()
  end

  defp create_default_settings(user_id) do
    %NotificationSetting{}
    |> NotificationSetting.changeset(%{user_id: user_id})
    |> Repo.insert()
  end

  # --- Conversation Mutes ---

  @doc """
  Mutes a conversation for a user. Optionally accepts a muted_until timestamp.
  """
  def mute_conversation(user_id, conversation_id, opts \\ %{}) do
    muted_until = Map.get(opts, :muted_until) || Map.get(opts, "muted_until")

    attrs = %{
      user_id: user_id,
      conversation_id: conversation_id,
      muted_until: muted_until
    }

    case get_conversation_mute(user_id, conversation_id) do
      nil ->
        %ConversationMute{}
        |> ConversationMute.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> ConversationMute.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Unmutes a conversation for a user.
  """
  def unmute_conversation(user_id, conversation_id) do
    case get_conversation_mute(user_id, conversation_id) do
      nil -> {:ok, :already_unmuted}
      mute -> Repo.delete(mute)
    end
  end

  @doc """
  Checks if a conversation is muted for a user.
  """
  def conversation_muted?(user_id, conversation_id) do
    case get_conversation_mute(user_id, conversation_id) do
      nil ->
        false

      %ConversationMute{muted_until: nil} ->
        true

      %ConversationMute{muted_until: until} ->
        DateTime.compare(until, DateTime.utc_now()) == :gt
    end
  end

  @doc """
  Checks if a notification type is enabled for a user.
  """
  def notification_enabled?(user_id, type) when type in [:new_message, :group_invite, :contact_request] do
    case get_user_settings(user_id) do
      {:ok, %{mute_all: true}} ->
        false

      {:ok, settings} ->
        case type do
          :new_message -> settings.message_notifications
          :group_invite -> settings.group_notifications
          :contact_request -> settings.contact_notifications
        end

      _ ->
        true
    end
  end

  defp get_conversation_mute(user_id, conversation_id) do
    ConversationMute
    |> where([m], m.user_id == ^user_id and m.conversation_id == ^conversation_id)
    |> Repo.one()
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end
end
