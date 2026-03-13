defmodule WhisprNotifications.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", ""

    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, :binary_id, null: false
      add :token, :text, null: false
      add :platform, :string, null: false
      add :device_id, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:devices, [:user_id])
    create unique_index(:devices, [:token], name: :devices_token_unique_index)
    create unique_index(:devices, [:user_id, :device_id], name: :devices_user_device_unique_index)
    create index(:devices, [:platform])
    create index(:devices, [:active])
  end
end
