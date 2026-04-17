defmodule WhisprNotifications.Repo do
  use Ecto.Repo,
    otp_app: :whispr_notification,
    adapter: Ecto.Adapters.Postgres
end
