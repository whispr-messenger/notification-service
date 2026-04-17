defmodule WhisprNotificationsWeb.NotificationsControllerTest do
  use WhisprNotifications.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Router

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

  test "POST /api/v1/notifications returns 201 with serialized notification", %{token: token} do
    body = %{
      "user_id" => "ctrl-u-1",
      "type" => "message",
      "title" => "Hi",
      "body" => "There",
      "context" => %{"conversation_id" => "c-1"}
    }

    conn =
      :post
      |> conn("/api/v1/notifications", body)
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> Router.call([])

    assert conn.status == 201
    decoded = Jason.decode!(conn.resp_body)
    assert decoded["user_id"] == "ctrl-u-1"
    assert decoded["type"] == "message"
    assert decoded["title"] == "Hi"
    assert is_binary(decoded["id"])
    assert is_binary(decoded["created_at"])
  end

  test "POST /api/v1/notifications returns 400 on validation errors", %{token: token} do
    conn =
      :post
      |> conn("/api/v1/notifications", %{"type" => "message"})
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> Router.call([])

    assert conn.status == 400
    decoded = Jason.decode!(conn.resp_body)
    assert is_list(decoded["errors"])
    assert "user_id est requis" in decoded["errors"]
  end

  test "POST /api/v1/notifications returns 401 without a bearer token" do
    conn =
      :post
      |> conn("/api/v1/notifications", %{"user_id" => "u"})
      |> put_req_header("content-type", "application/json")
      |> Router.call([])

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
  end

  defp sign_token(priv, kid) do
    now = System.system_time(:second)

    claims = %{
      "sub" => "user-ctrl",
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
