defmodule WhisprNotifications.Repo.Migrations.AddMentionsOnlyToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :mentions_only, :boolean, default: false, null: false
    end
  end
end
