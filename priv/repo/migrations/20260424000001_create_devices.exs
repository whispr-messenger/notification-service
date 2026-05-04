defmodule WhisprNotifications.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      # user_id stocké en string pour rester aligné avec
      # notification_history et la convention du service (les JWT
      # transportent le sub en UUID-string, pas besoin de cast côté base).
      add :user_id, :string, null: false
      add :device_id, :string, null: false
      add :fcm_token, :text, null: false
      add :platform, :string, null: false
      add :app_version, :string
      add :last_error, :string
      add :last_error_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Un même (user, device_id) ne peut exister qu'une seule fois vivant —
    # on soft-delete avec deleted_at IS NOT NULL, l'index unique partial
    # laisse passer les ressuscitations sous un nouvel uuid.
    create unique_index(:devices, [:user_id, :device_id],
             where: "deleted_at IS NULL",
             name: :devices_user_device_active_index
           )

    create index(:devices, [:user_id])
    create index(:devices, [:fcm_token])
    create index(:devices, [:last_error])
  end
end
