defmodule WhisprNotifications.Repo.Migrations.AddWebPushFieldsToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :wp_p256dh, :text
      add :wp_auth, :text
    end

    # platform est stocké en string sans check constraint DB — pas de migration
    # supplémentaire pour étendre l'enum (la validation est côté Ecto).
  end
end
