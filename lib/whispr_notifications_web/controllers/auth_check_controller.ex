defmodule WhisprNotificationsWeb.AuthCheckController do
  use WhisprNotificationsWeb, :controller

  def show(conn, _params) do
    json(conn, %{"status" => "ok", "sub" => conn.assigns[:jwt_sub]})
  end
end
