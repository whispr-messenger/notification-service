defmodule WhisprNotificationsWeb.SettingsControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias WhisprNotifications.Test.AuthHelpers
  alias WhisprNotificationsWeb.Router

  setup do
    AuthHelpers.setup_jwt()
  end

  test "GET /api/settings/:id returns user settings JSON", %{token: token} do
    conn =
      :get
      |> conn("/api/settings/user-settings-1")
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == "user-settings-1"
    assert decoded["message_push_enabled"] == true
    assert decoded["message_email_enabled"] == false
    assert decoded["system_push_enabled"] == true
    assert decoded["marketing_push_enabled"] == false
  end

  test "PUT /api/settings/:id returns updated settings JSON", %{token: token} do
    conn =
      :put
      |> conn("/api/settings/user-settings-2", %{"message_push_enabled" => false})
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == "user-settings-2"
    assert decoded["message_push_enabled"] == false
  end

  test "PUT /api/settings/:id returns 422 when attrs are invalid", %{token: token} do
    conn =
      :put
      |> conn("/api/settings/user-settings-invalid", %{
        "quiet_hours_start" => "not-a-time"
      })
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 422
    assert %{"errors" => _} = Jason.decode!(conn.resp_body)
  end

  test "GET /api/settings/:id returns sensible defaults when no row exists", %{token: token} do
    uid = "user-fresh-" <> Integer.to_string(System.unique_integer([:positive]))

    conn =
      :get
      |> conn("/api/settings/" <> uid)
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == uid
    assert decoded["message_push_enabled"] == true
    assert decoded["system_push_enabled"] == true
  end
end
