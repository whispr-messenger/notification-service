defmodule WhisprNotifications.Repo.Migrations.CreateDeliveryAttempts do
  use Ecto.Migration

  def change do
    create table(:delivery_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :notification_id, :string, null: false
      add :device_id, :string
      add :status, :string, null: false
      add :error_code, :string
      add :error_message, :text
      add :response_data, :map, null: false, default: %{}
      add :retry_count, :integer, null: false, default: 0
      add :attempted_at, :utc_datetime, null: false
      add :next_retry_at, :utc_datetime
    end

    create index(:delivery_attempts, [:notification_id])
    create index(:delivery_attempts, [:device_id])
    create index(:delivery_attempts, [:next_retry_at])
  end
end
