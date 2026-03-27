defmodule WhisprNotificationsWeb.HealthController do
  use WhisprNotificationsWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def auth_check(conn, _params) do
    claims = conn.assigns[:jwt_claims] || %{}
    json(conn, %{status: "ok", sub: claims["sub"]})
  end
end
