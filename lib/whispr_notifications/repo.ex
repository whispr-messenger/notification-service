defmodule WhisprNotifications.Repo do
  use Ecto.Repo,
    otp_app: :whispr_notification,
    adapter: Ecto.Adapters.Postgres

  require Logger

  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, System.get_env("DATABASE_URL"))}
  end

  def health_check do
    query!("SELECT 1", [], timeout: 5_000)
    :ok
  rescue
    exception ->
      Logger.error("Database health check failed: #{inspect(exception)}")
      {:error, exception}
  end
end
