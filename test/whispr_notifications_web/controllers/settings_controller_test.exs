defmodule WhisprNotificationsWeb.SettingsControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.Router

  test "GET /api/settings/:id returns user settings JSON" do
    conn =
      :get
      |> conn("/api/settings/user-settings-1")
      |> Router.call([])

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == "user-settings-1"
    assert decoded["message_push_enabled"] == true
    assert decoded["message_email_enabled"] == false
    assert decoded["system_push_enabled"] == true
    assert decoded["marketing_push_enabled"] == false
  end

  test "PUT /api/settings/:id returns 204" do
    conn =
      :put
      |> conn("/api/settings/user-settings-2", %{"message_push_enabled" => false})
      |> Router.call([])

    assert conn.status == 204
  end
end
