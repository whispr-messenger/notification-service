defmodule WhisprNotifications.Preferences.Manager do
  @moduledoc """
  API pour gérer et lire les préférences de notifications.
  Persiste via Ecto sur PostgreSQL.
  """

  alias WhisprNotifications.Preferences.{UserSettings, ConversationSettings}
  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotifications.Repo

  defmodule Behaviour do
    @callback get_user_settings(String.t()) ::
                {:ok, UserSettings.t()} | {:error, term()}

    @callback get_conversation_settings(String.t(), String.t()) ::
                {:ok, ConversationSettings.t()} | {:error, term()}
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
    user_ok =
      case get_user_settings(notif.user_id) do
        {:ok, us} -> not UserSettings.quiet_now?(us, now)
        _ -> true
      end

    conv_ok =
      if is_nil(notif.conversation_id) do
        true
      else
        case get_conversation_settings(notif.user_id, notif.conversation_id) do
          {:ok, cs} -> not ConversationSettings.muted_now?(cs, now)
          _ -> true
        end
      end

    user_ok and conv_ok
  end

  defp normalize_attrs(attrs, key, value) when is_map(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put(key, value)
  end
end
