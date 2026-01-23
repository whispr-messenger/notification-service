defmodule WhisprNotificationsWeb.FallbackController do
  use WhisprNotificationsWeb, :controller

  def call(conn, {:error, :not_found}) do
    send_resp(conn, 404, "")
  end

  def call(conn, {:error, :bad_request}) do
    send_resp(conn, 400, "")
  end

  def call(conn, _error) do
    send_resp(conn, 500, "")
  end
end
