defmodule WhisprNotificationsWeb.DevicesControllerTest do
  use WhisprNotifications.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Devices
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Router

  @jwt_sub "device-owner-1"

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_devices_ctrl_test

    original = Application.get_env(:whispr_notification, :jwt)

    Application.put_env(
      :whispr_notification,
      :jwt,
      jwks_url: "http://auth-service/auth/.well-known/jwks.json",
      issuer: "whispr-auth",
      audience: "whispr-notification",
      allowed_algs: ["ES256"],
      jwks_refresh_interval_ms: 60_000,
      jwks_cache_server: server
    )

    start_supervised!({JwksCache, [name: server, http_get_fun: http_get_fun]})

    token = sign_token(ES256JwtFixtures.primary_private_jwk(), ES256JwtFixtures.primary_kid())

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:whispr_notification, :jwt)
      else
        Application.put_env(:whispr_notification, :jwt, original)
      end
    end)

    {:ok, token: token}
  end

  describe "POST /api/v1/devices — registration" do
    test "returns 201 on first registration and persists the device", %{token: token} do
      body = %{
        "device_id" => "dev-android-001",
        "fcm_token" => "fcm-token-value-abc",
        "platform" => "android",
        "app_version" => "1.2.3"
      }

      conn = post_devices(token, body)

      assert conn.status == 201
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["user_id"] == @jwt_sub
      assert decoded["device_id"] == "dev-android-001"
      assert decoded["platform"] == "android"
      assert decoded["app_version"] == "1.2.3"
      assert is_binary(decoded["id"])

      assert [device] = Devices.list_active_for_user(@jwt_sub)
      assert device.fcm_token == "fcm-token-value-abc"
    end

    test "returns 200 when the same device_id is re-registered (idempotent upsert)",
         %{token: token} do
      body = %{
        "device_id" => "dev-ios-002",
        "fcm_token" => "fcm-token-original",
        "platform" => "ios",
        "app_version" => "1.0.0"
      }

      assert post_devices(token, body).status == 201

      refreshed =
        body
        |> Map.put("fcm_token", "fcm-token-rotated")
        |> Map.put("app_version", "1.0.1")

      conn = post_devices(token, refreshed)
      assert conn.status == 200
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["app_version"] == "1.0.1"

      assert [device] = Devices.list_active_for_user(@jwt_sub)
      assert device.fcm_token == "fcm-token-rotated"
    end

    test "re-registering a soft-deleted device revives it with 200", %{token: token} do
      body = %{
        "device_id" => "dev-revive-1",
        "fcm_token" => "fcm-a",
        "platform" => "android"
      }

      assert post_devices(token, body).status == 201
      assert delete_device(token, "dev-revive-1").status == 204
      assert Devices.list_active_for_user(@jwt_sub) == []

      conn = post_devices(token, Map.put(body, "fcm_token", "fcm-b"))
      assert conn.status == 200
      assert [device] = Devices.list_active_for_user(@jwt_sub)
      assert device.fcm_token == "fcm-b"
      assert is_nil(device.deleted_at)
    end

    test "returns 401 without a bearer token" do
      conn =
        :post
        |> conn("/api/v1/devices", %{"device_id" => "x", "fcm_token" => "y", "platform" => "ios"})
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 401
    end

    test "returns 400 when required fields are missing", %{token: token} do
      conn = post_devices(token, %{"platform" => "android"})
      assert conn.status == 400
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["errors"]["device_id"] == ["can't be blank"]
      assert decoded["errors"]["fcm_token"] == ["can't be blank"]
    end

    test "returns 400 when platform is not in the allowed set", %{token: token} do
      conn =
        post_devices(token, %{
          "device_id" => "dev-x",
          "fcm_token" => "t",
          "platform" => "windows"
        })

      assert conn.status == 400
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["errors"]["platform"] == ["is invalid"]
    end
  end

  describe "DELETE /api/v1/devices/:device_id — unregistration" do
    test "returns 204 and soft-deletes the device", %{token: token} do
      body = %{
        "device_id" => "dev-to-delete",
        "fcm_token" => "t",
        "platform" => "ios"
      }

      assert post_devices(token, body).status == 201
      assert Devices.list_active_for_user(@jwt_sub) != []

      conn = delete_device(token, "dev-to-delete")
      assert conn.status == 204
      assert conn.resp_body == ""
      assert Devices.list_active_for_user(@jwt_sub) == []
    end

    test "is idempotent — returns 204 even if the device never existed", %{token: token} do
      conn = delete_device(token, "dev-never-registered")
      assert conn.status == 204
    end

    test "is idempotent — returns 204 even if already soft-deleted", %{token: token} do
      body = %{"device_id" => "dev-twice", "fcm_token" => "t", "platform" => "android"}
      assert post_devices(token, body).status == 201
      assert delete_device(token, "dev-twice").status == 204
      assert delete_device(token, "dev-twice").status == 204
    end

    test "does not delete another user's device with the same device_id", %{token: token} do
      body = %{"device_id" => "dev-shared", "fcm_token" => "mine", "platform" => "android"}
      assert post_devices(token, body).status == 201

      # Seed a device belonging to a different user with the same device_id.
      {:ok, _device} =
        Devices.upsert(%{
          "user_id" => "other-user",
          "device_id" => "dev-shared",
          "fcm_token" => "theirs",
          "platform" => "ios"
        })

      assert delete_device(token, "dev-shared").status == 204
      assert Devices.list_active_for_user(@jwt_sub) == []
      assert [_] = Devices.list_active_for_user("other-user")
    end

    test "returns 401 without a bearer token" do
      conn =
        :delete
        |> conn("/api/v1/devices/dev-x")
        |> Router.call([])

      assert conn.status == 401
    end
  end

  defp post_devices(token, body) do
    :post
    |> conn("/api/v1/devices", body)
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> Router.call([])
  end

  defp delete_device(token, device_id) do
    :delete
    |> conn("/api/v1/devices/" <> device_id)
    |> put_req_header("authorization", "Bearer " <> token)
    |> Router.call([])
  end

  defp sign_token(priv, kid) do
    now = System.system_time(:second)

    claims = %{
      "sub" => @jwt_sub,
      "iss" => "whispr-auth",
      "aud" => "whispr-notification",
      "exp" => now + 3600
    }

    {_, token} =
      priv
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
