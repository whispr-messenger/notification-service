defmodule WhisprNotifications.Repo.Migrations.AddMentionsOnlyToConversationSettings do
  use Ecto.Migration

  # Nullable so a conversation row that hasn't set the override falls back to
  # the user-level value at filter time. We never want to silently coerce an
  # unset override to false.
  def change do
    alter table(:conversation_settings) do
      add :mentions_only, :boolean, null: true
    end
  end
end
