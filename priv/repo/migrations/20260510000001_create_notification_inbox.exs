defmodule WhisprNotifications.Repo.Migrations.CreateNotificationInbox do
  use Ecto.Migration

  def change do
    create table(:notification_inbox, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, :uuid, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :read_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:notification_inbox, [:user_id, :created_at], order: [created_at: :desc])
    create index(:notification_inbox, [:user_id, :read_at], where: "read_at IS NULL")
    create index(:notification_inbox, [:user_id, :event_type])
  end
end
