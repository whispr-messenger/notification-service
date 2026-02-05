defmodule WhisprNotificationsWeb.HealthControllerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias WhisprNotificationsWeb.Router

  test "GET /api/v1/health returns 200" do
    conn =
      :get
      |> conn("/api/v1/health")
      |> Router.call([])

    assert conn.status == 200
  end
end
