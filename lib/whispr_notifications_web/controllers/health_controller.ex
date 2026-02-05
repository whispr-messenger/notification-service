defmodule WhisprNotificationsWeb.HealthController do
  use WhisprNotificationsWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
