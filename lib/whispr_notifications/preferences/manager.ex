defmodule WhisprNotifications.Preferences.Manager do
  @moduledoc """
  API pour gérer et lire les préférences de notifications.
  Persiste via Ecto sur PostgreSQL.
  """

  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotifications.Preferences.{ConversationSettings, UserSettings}
  alias WhisprNotifications.Repo

  defmodule Behaviour do
    @moduledoc "Behaviour pour les dépendances injectables du Manager de préférences."

    @callback get_user_settings(String.t()) ::
                {:ok, WhisprNotifications.Preferences.UserSettings.t()} | {:error, term()}

    @callback get_conversation_settings(String.t(), String.t()) ::
                {:ok, WhisprNotifications.Preferences.ConversationSettings.t()} | {:error, term()}
  end

  @behaviour Behaviour

  @impl true
  @spec get_user_settings(String.t()) :: {:ok, UserSettings.t()}
  def get_user_settings(user_id) do
    case Repo.get_by(UserSettings, user_id: user_id) do
      nil -> {:ok, %UserSettings{user_id: user_id}}
      %UserSettings{} = s -> {:ok, s}
    end
  end

  @spec update_user_settings(String.t(), map()) ::
          {:ok, UserSettings.t()} | {:error, Ecto.Changeset.t()}
  def update_user_settings(user_id, attrs) when is_binary(user_id) do
    existing =
      case Repo.get_by(UserSettings, user_id: user_id) do
        nil -> %UserSettings{}
        s -> s
      end

    existing
    |> UserSettings.changeset(normalize_attrs(attrs, "user_id", user_id))
    |> Repo.insert_or_update()
  end

  @impl true
  @spec get_conversation_settings(String.t(), String.t() | nil) ::
          {:ok, ConversationSettings.t()}
  def get_conversation_settings(user_id, nil) do
    {:ok, %ConversationSettings{user_id: user_id, conversation_id: nil}}
  end

  def get_conversation_settings(user_id, conversation_id) do
    case Repo.get_by(ConversationSettings,
           user_id: user_id,
           conversation_id: conversation_id
         ) do
      nil ->
        {:ok, %ConversationSettings{user_id: user_id, conversation_id: conversation_id}}

      %ConversationSettings{} = s ->
        {:ok, s}
    end
  end

  @spec set_muted(String.t(), String.t(), boolean(), keyword()) ::
          {:ok, ConversationSettings.t()} | {:error, Ecto.Changeset.t()}
  def set_muted(user_id, conversation_id, muted, opts \\ [])
      when is_binary(user_id) and is_binary(conversation_id) and is_boolean(muted) do
    existing =
      case Repo.get_by(ConversationSettings,
             user_id: user_id,
             conversation_id: conversation_id
           ) do
        nil -> %ConversationSettings{}
        s -> s
      end

    attrs = %{
      "user_id" => user_id,
      "conversation_id" => conversation_id,
      "muted" => muted,
      "mute_until" => if(muted, do: Keyword.get(opts, :mute_until), else: nil)
    }

    existing
    |> ConversationSettings.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec allowed_for_notification?(Notification.t(), DateTime.t()) :: boolean()
  def allowed_for_notification?(%Notification{} = notif, now \\ DateTime.utc_now()) do
    user_settings =
      case get_user_settings(notif.user_id) do
        {:ok, us} -> us
        _ -> nil
      end

    conv_settings =
      if is_nil(notif.conversation_id) do
        nil
      else
        case get_conversation_settings(notif.user_id, notif.conversation_id) do
          {:ok, cs} -> cs
          _ -> nil
        end
      end

    user_ok = is_nil(user_settings) or not UserSettings.quiet_now?(user_settings, now)
    conv_ok = is_nil(conv_settings) or not ConversationSettings.muted_now?(conv_settings, now)
    mention_ok = mention_allowed?(notif, user_settings, conv_settings)

    user_ok and conv_ok and mention_ok
  end

  # `mentions_only` blocks message-type notifications that are not @-mentions
  # for the recipient. The flag is read with conversation-level overriding
  # user-level (nil at conversation level falls back to the user value).
  # Non-:message notifs (system, group invites, …) are never affected.
  defp mention_allowed?(%Notification{type: :message} = notif, user_settings, conv_settings) do
    case effective_mentions_only(user_settings, conv_settings) do
      true -> mentioned?(notif)
      _ -> true
    end
  end

  defp mention_allowed?(_notif, _us, _cs), do: true

  defp effective_mentions_only(_us, %ConversationSettings{mentions_only: v}) when is_boolean(v),
    do: v

  defp effective_mentions_only(%UserSettings{mentions_only: v}, _cs) when is_boolean(v), do: v
  defp effective_mentions_only(_us, _cs), do: false

  defp mentioned?(%Notification{metadata: %{"mentioned" => true}}), do: true
  defp mentioned?(%Notification{metadata: %{mentioned: true}}), do: true
  defp mentioned?(_), do: false

  defp normalize_attrs(attrs, key, value) when is_map(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put(key, value)
  end
end
