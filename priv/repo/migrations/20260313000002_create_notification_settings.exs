defmodule WhisprNotifications.Repo.Migrations.CreateNotificationSettings do
  use Ecto.Migration

  def change do
    create table(:notification_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, :binary_id, null: false
      add :mute_all, :boolean, null: false, default: false
      add :message_notifications, :boolean, null: false, default: true
      add :group_notifications, :boolean, null: false, default: true
      add :contact_notifications, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:notification_settings, [:user_id], name: :notification_settings_user_id_unique_index)
  end
end
