defmodule WhisprNotificationsWeb.DevicesControllerWebPushTest do
  @moduledoc """
  Tests DevicesController pour l'enregistrement de devices web_push (VAPID iOS PWA).
  """
  use WhisprNotifications.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Devices
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Router

  @jwt_sub "wp-owner-001"

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_wp_ctrl_test

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

  describe "POST /api/v1/devices — web_push" do
    test "enregistre un device web_push avec endpoint + keys", %{token: token} do
      body = %{
        "device_id" => "pwa-safari-ios-001",
        "fcm_token" => "https://web.push.apple.com/FAKE_VAPID_ENDPOINT",
        "platform" => "web_push",
        "keys" => %{
          "p256dh" => "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
          "auth" => "n_auth_secret_base64url"
        }
      }

      conn = post_devices(token, body)

      assert conn.status == 201
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["platform"] == "web_push"
      assert decoded["device_id"] == "pwa-safari-ios-001"

      [device] = Devices.list_active_for_user(@jwt_sub)
      assert device.fcm_token == "https://web.push.apple.com/FAKE_VAPID_ENDPOINT"
      assert device.wp_p256dh == "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c"
      assert device.wp_auth == "n_auth_secret_base64url"
      assert device.platform == "web_push"
    end

    test "accepte le champ 'endpoint' comme alias de 'fcm_token' pour web_push", %{token: token} do
      body = %{
        "device_id" => "pwa-safari-ios-002",
        "endpoint" => "https://web.push.apple.com/ENDPOINT_ALIAS",
        "platform" => "web_push",
        "keys" => %{
          "p256dh" => "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
          "auth" => "n_auth_secret_base64url"
        }
      }

      conn = post_devices(token, body)

      assert conn.status == 201
      [device] = Devices.list_active_for_user(@jwt_sub)
      assert device.fcm_token == "https://web.push.apple.com/ENDPOINT_ALIAS"
    end

    test "retourne 400 si platform web_push sans keys", %{token: token} do
      body = %{
        "device_id" => "pwa-no-keys",
        "fcm_token" => "https://web.push.apple.com/FAKE",
        "platform" => "web_push"
      }

      conn = post_devices(token, body)

      assert conn.status == 400
      decoded = Jason.decode!(conn.resp_body)
      assert Map.has_key?(decoded, "errors")
    end

    test "retourne 400 si platform web_push avec keys incomplètes (auth manquant)", %{
      token: token
    } do
      body = %{
        "device_id" => "pwa-partial-keys",
        "fcm_token" => "https://web.push.apple.com/FAKE",
        "platform" => "web_push",
        "keys" => %{"p256dh" => "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c"}
      }

      conn = post_devices(token, body)

      assert conn.status == 400
    end

    test "retourne 200 quand le même device_id web_push est re-enregistré (upsert)", %{
      token: token
    } do
      body = %{
        "device_id" => "pwa-upsert-test",
        "fcm_token" => "https://web.push.apple.com/ORIGINAL",
        "platform" => "web_push",
        "keys" => %{
          "p256dh" => "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
          "auth" => "n_auth_secret_base64url"
        }
      }

      assert post_devices(token, body).status == 201

      # re-register avec un nouvel endpoint
      refreshed = Map.put(body, "fcm_token", "https://web.push.apple.com/NEW_ENDPOINT")
      conn = post_devices(token, refreshed)
      assert conn.status == 200

      # seul le dernier token est actif
      [device] = Devices.list_active_for_user(@jwt_sub)
      assert device.fcm_token == "https://web.push.apple.com/NEW_ENDPOINT"
    end
  end

  defp post_devices(token, body) do
    :post
    |> conn("/api/v1/devices", body)
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
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
