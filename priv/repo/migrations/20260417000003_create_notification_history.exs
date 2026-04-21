defmodule WhisprNotifications.Repo.Migrations.CreateNotificationHistory do
  use Ecto.Migration

  def change do
    create table(:notification_history, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, :string, null: false
      add :conversation_id, :string
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :context, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :created_at, :utc_datetime, null: false
      add :read_at, :utc_datetime
    end

    create index(:notification_history, [:user_id])
    create index(:notification_history, [:user_id, :created_at])
    create index(:notification_history, [:conversation_id])
  end
end
