defmodule WhisprNotificationsWeb.BadgeControllerExtraTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.BadgeController

  test "show/2 without :jwt_sub returns 401 with missing_user error" do
    conn =
      :get
      |> conn("/api/v1/badge")
      |> BadgeController.show(%{})

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body) == %{"error" => "missing_user"}
  end
end
