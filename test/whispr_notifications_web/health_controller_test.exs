defmodule WhisprNotificationsWeb.HealthControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.Router

  test "GET /api/health returns 200" do
    conn =
      :get
      |> conn("/api/health")
      |> Router.call([])

    assert conn.status == 200
  end
end
