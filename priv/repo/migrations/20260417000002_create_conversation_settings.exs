defmodule WhisprNotifications.Repo.Migrations.CreateConversationSettings do
  use Ecto.Migration

  def change do
    create table(:conversation_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :conversation_id, :string, null: false
      add :muted, :boolean, null: false, default: false
      add :mute_until, :utc_datetime
      add :priority, :string, null: false, default: "normal"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_settings, [:user_id, :conversation_id])
    create index(:conversation_settings, [:user_id])
    create index(:conversation_settings, [:mute_until])
  end
end
