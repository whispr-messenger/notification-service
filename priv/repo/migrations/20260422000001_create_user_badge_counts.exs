defmodule WhisprNotifications.Repo.Migrations.CreateUserBadgeCounts do
  use Ecto.Migration

  def change do
    create table(:user_badge_counts, primary_key: false) do
      add :user_id, :string, primary_key: true
      add :unread_count, :integer, null: false, default: 0
      add :updated_at, :utc_datetime, null: false
    end
  end
end
