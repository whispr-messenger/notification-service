defmodule WhisprNotificationsWeb.HealthController do
  use WhisprNotificationsWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def metrics(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "")
  end
end
