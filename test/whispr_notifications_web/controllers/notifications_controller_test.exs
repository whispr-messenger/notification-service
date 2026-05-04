defmodule WhisprNotificationsWeb.NotificationsControllerTest do
  use WhisprNotifications.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Notifications.History
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Router

  @jwt_sub "user-ctrl"

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_notif_ctrl_test

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

  describe "POST /api/v1/notifications — authorization" do
    test "returns 201 when body user_id matches the JWT sub", %{token: token} do
      body = %{
        "user_id" => @jwt_sub,
        "type" => "message",
        "title" => "Hi",
        "body" => "There",
        "context" => %{"conversation_id" => "c-1"}
      }

      conn = post_notifications(token, body)

      assert conn.status == 201
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["user_id"] == @jwt_sub
      assert decoded["type"] == "message"
      assert is_binary(decoded["id"])
    end

    test "returns 403 when body user_id differs from JWT sub and persists nothing",
         %{token: token} do
      victim_id = "victim-user-id"

      body = %{
        "user_id" => victim_id,
        "type" => "message",
        "title" => "Impersonation",
        "body" => "Should never be delivered",
        "context" => %{}
      }

      conn = post_notifications(token, body)

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
      assert History.list_for_user(victim_id) == []
      assert History.list_for_user(@jwt_sub) == []
    end

    test "falls back to JWT sub when body has no user_id", %{token: token} do
      body = %{
        "type" => "system",
        "title" => "No user_id in body",
        "body" => "Should use JWT sub",
        "context" => %{}
      }

      conn = post_notifications(token, body)

      assert conn.status == 201
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["user_id"] == @jwt_sub
    end

    test "treats empty-string user_id like missing and falls back to JWT sub",
         %{token: token} do
      body = %{
        "user_id" => "",
        "type" => "message",
        "title" => "Empty user_id",
        "body" => "Fallback expected",
        "context" => %{}
      }

      conn = post_notifications(token, body)

      assert conn.status == 201
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["user_id"] == @jwt_sub
    end
  end

  describe "POST /api/v1/notifications — validation and auth plug" do
    test "returns 400 on validation errors (missing title)", %{token: token} do
      body = %{"type" => "message", "body" => "no title"}

      conn = post_notifications(token, body)

      assert conn.status == 400
      decoded = Jason.decode!(conn.resp_body)
      assert is_list(decoded["errors"])
      assert "title est requis" in decoded["errors"]
    end

    test "returns 401 without a bearer token" do
      conn =
        :post
        |> conn("/api/v1/notifications", %{"user_id" => "u"})
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end
  end

  defp post_notifications(token, body) do
    :post
    |> conn("/api/v1/notifications", body)
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
