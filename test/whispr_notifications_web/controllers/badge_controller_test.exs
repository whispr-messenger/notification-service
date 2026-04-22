defmodule WhisprNotificationsWeb.BadgeControllerTest do
  use WhisprNotifications.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Badges
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Router

  setup do
    kid = ES256JwtFixtures.primary_kid()
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    payload = %{"keys" => [jwks_key]}
    http_get_fun = fn _url -> {:ok, %{status: 200, body: payload}} end

    Application.put_env(
      :whispr_notification,
      :jwt,
      jwks_url: "http://auth-service/auth/.well-known/jwks.json",
      issuer: "whispr-auth",
      audience: "whispr-notification",
      allowed_algs: ["ES256"],
      jwks_refresh_interval_ms: 60_000,
      jwks_cache_server: :jwks_cache_badge_test
    )

    start_supervised!({JwksCache, [name: :jwks_cache_badge_test, http_get_fun: http_get_fun]})

    token = sign_token(ES256JwtFixtures.primary_private_jwk(), kid, "user-badge")
    {:ok, token: token}
  end

  test "GET /api/v1/badge without auth returns 401" do
    conn = :get |> conn("/api/v1/badge") |> Router.call([])
    assert conn.status == 401
  end

  test "GET /api/v1/badge returns the unread count for the user", %{token: token} do
    Badges.set("user-badge", 5)

    conn =
      :get
      |> conn("/api/v1/badge")
      |> put_req_header("authorization", "Bearer " <> token)
      |> Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"unread_count" => 5}
  end

  test "GET /api/v1/badge returns 0 when user has no row", %{token: token} do
    conn =
      :get
      |> conn("/api/v1/badge")
      |> put_req_header("authorization", "Bearer " <> token)
      |> Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"unread_count" => 0}
  end

  defp sign_token(private_jwk, kid, sub) do
    now = System.system_time(:second)

    claims = %{
      "sub" => sub,
      "iss" => "whispr-auth",
      "aud" => "whispr-notification",
      "exp" => now + 3600
    }

    {_, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
