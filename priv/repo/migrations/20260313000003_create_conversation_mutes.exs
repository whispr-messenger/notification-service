defmodule WhisprNotifications.Repo.Migrations.CreateConversationMutes do
  use Ecto.Migration

  def change do
    create table(:conversation_mutes, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, :binary_id, null: false
      add :conversation_id, :binary_id, null: false
      add :muted_until, :utc_datetime, null: true

      timestamps()
    end

    create unique_index(:conversation_mutes, [:user_id, :conversation_id],
      name: :conversation_mutes_user_conversation_unique_index
    )

    create index(:conversation_mutes, [:user_id])
    create index(:conversation_mutes, [:conversation_id])
  end
end
