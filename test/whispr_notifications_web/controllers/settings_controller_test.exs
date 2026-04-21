defmodule WhisprNotificationsWeb.SettingsControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.Router

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

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

  test "PUT /api/settings/:id persists changes visible to a subsequent GET" do
    user_id = unique_id("user-settings")

    put_conn =
      :put
      |> conn("/api/settings/#{user_id}", %{
        "message_push_enabled" => false,
        "marketing_push_enabled" => true,
        "language" => "fr",
        "timezone" => "Europe/Paris"
      })
      |> Router.call([])

    assert put_conn.status == 204

    get_conn =
      :get
      |> conn("/api/settings/#{user_id}")
      |> Router.call([])

    assert get_conn.status == 200
    decoded = Jason.decode!(get_conn.resp_body)
    assert decoded["user_id"] == user_id
    assert decoded["message_push_enabled"] == false
    assert decoded["marketing_push_enabled"] == true
    assert decoded["language"] == "fr"
    assert decoded["timezone"] == "Europe/Paris"
  end

  test "PUT /api/settings/:id returns 422 on invalid attributes" do
    user_id = unique_id("user-settings")

    conn =
      :put
      |> conn("/api/settings/#{user_id}", %{"quiet_hours_start" => "not-a-time"})
      |> Router.call([])

    assert conn.status == 422
    assert %{"errors" => errors} = Jason.decode!(conn.resp_body)
    assert Map.has_key?(errors, "quiet_hours_start")
  end
end
