defmodule WhisprNotifications.Repo.Migrations.CreateUserSettings do
  use Ecto.Migration

  def change do
    create table(:user_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :language, :string
      add :timezone, :string
      add :message_push_enabled, :boolean, null: false, default: true
      add :message_email_enabled, :boolean, null: false, default: false
      add :system_push_enabled, :boolean, null: false, default: true
      add :marketing_push_enabled, :boolean, null: false, default: false
      add :quiet_hours_start, :time
      add :quiet_hours_end, :time

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_settings, [:user_id])
  end
end
