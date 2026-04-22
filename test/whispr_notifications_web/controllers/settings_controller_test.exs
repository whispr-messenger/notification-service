defmodule WhisprNotificationsWeb.SettingsControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.SettingsController

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  # The /settings routes sit behind the :jwt_authenticated pipeline
  # (WHISPR-1028). Unit tests call the controller actions directly so they
  # don't need to stage JWKS + sign a test token; the auth wiring itself is
  # exercised by the jwt_guard_integration_test suite.

  test "show/2 returns user settings JSON" do
    conn =
      :get
      |> conn("/api/settings/user-settings-1")
      |> SettingsController.show(%{"id" => "user-settings-1"})

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == "user-settings-1"
    assert decoded["message_push_enabled"] == true
    assert decoded["message_email_enabled"] == false
    assert decoded["system_push_enabled"] == true
    assert decoded["marketing_push_enabled"] == false
  end

  test "update/2 returns 204" do
    conn =
      :put
      |> conn("/api/settings/user-settings-2")
      |> SettingsController.update(%{
        "id" => "user-settings-2",
        "message_push_enabled" => false
      })

    assert conn.status == 204
  end

  test "update/2 persists changes visible to a subsequent show/2" do
    user_id = unique_id("user-settings")

    put_conn =
      :put
      |> conn("/api/settings/#{user_id}")
      |> SettingsController.update(%{
        "id" => user_id,
        "message_push_enabled" => false,
        "marketing_push_enabled" => true,
        "language" => "fr",
        "timezone" => "Europe/Paris"
      })

    assert put_conn.status == 204

    get_conn =
      :get
      |> conn("/api/settings/#{user_id}")
      |> SettingsController.show(%{"id" => user_id})

    assert get_conn.status == 200
    decoded = Jason.decode!(get_conn.resp_body)
    assert decoded["user_id"] == user_id
    assert decoded["message_push_enabled"] == false
    assert decoded["marketing_push_enabled"] == true
    assert decoded["language"] == "fr"
    assert decoded["timezone"] == "Europe/Paris"
  end

  test "update/2 returns 422 on invalid attributes" do
    user_id = unique_id("user-settings")

    conn =
      :put
      |> conn("/api/settings/#{user_id}")
      |> SettingsController.update(%{
        "id" => user_id,
        "quiet_hours_start" => "not-a-time"
      })

    assert conn.status == 422
    assert %{"errors" => errors} = Jason.decode!(conn.resp_body)
    assert Map.has_key?(errors, "quiet_hours_start")
  end

  # WHISPR-1113: /v1/settings resolves the current user from the JWT claim
  # that the Authenticate plug assigns to :jwt_sub, rather than pattern-
  # matching on a path param (which was 500-ing when the gateway stripped
  # the /:id segment).

  test "show/2 without :id uses jwt_sub assign" do
    user_id = unique_id("jwt-user")

    conn =
      :get
      |> conn("/api/v1/settings")
      |> Plug.Conn.assign(:jwt_sub, user_id)
      |> SettingsController.show(%{})

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == user_id
  end

  test "show/2 without :id and without jwt_sub returns 401" do
    conn =
      :get
      |> conn("/api/v1/settings")
      |> SettingsController.show(%{})

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body) == %{"error" => "missing_user"}
  end

  test "update/2 without :id uses jwt_sub assign" do
    user_id = unique_id("jwt-user")

    conn =
      :put
      |> conn("/api/v1/settings")
      |> Plug.Conn.assign(:jwt_sub, user_id)
      |> SettingsController.update(%{"message_push_enabled" => false})

    assert conn.status == 204

    get_conn =
      :get
      |> conn("/api/v1/settings")
      |> Plug.Conn.assign(:jwt_sub, user_id)
      |> SettingsController.show(%{})

    assert get_conn.status == 200
    decoded = Jason.decode!(get_conn.resp_body)
    assert decoded["user_id"] == user_id
    assert decoded["message_push_enabled"] == false
  end

  test "update/2 without :id and without jwt_sub returns 401" do
    conn =
      :put
      |> conn("/api/v1/settings")
      |> SettingsController.update(%{"message_push_enabled" => false})

    assert conn.status == 401
  end
end
