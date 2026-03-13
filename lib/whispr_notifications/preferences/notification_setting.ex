defmodule WhisprNotifications.Preferences.NotificationSetting do
  @moduledoc """
  Ecto schema for per-user notification preferences.
  Controls which types of push notifications a user receives.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_settings" do
    field :user_id, :binary_id
    field :mute_all, :boolean, default: false
    field :message_notifications, :boolean, default: true
    field :group_notifications, :boolean, default: true
    field :contact_notifications, :boolean, default: true

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:user_id, :mute_all, :message_notifications, :group_notifications, :contact_notifications])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id, name: :notification_settings_user_id_unique_index)
  end

  def update_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:mute_all, :message_notifications, :group_notifications, :contact_notifications])
  end
end
