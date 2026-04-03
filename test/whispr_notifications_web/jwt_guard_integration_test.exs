defmodule WhisprNotificationsWeb.JwtGuardIntegrationTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
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
      jwks_cache_server: :jwks_cache_integration_test
    )

<<<<<<< WHISPR-552-notification
    start_supervised!(
      {JwksCache, [name: :jwks_cache_integration_test, http_get_fun: http_get_fun]}
    )
=======
    start_supervised!({JwksCache, [name: :jwks_cache_integration_test, http_get_fun: http_get_fun]})
>>>>>>> main

    token = sign_es256_token(ES256JwtFixtures.primary_private_jwk(), kid)
    {:ok, token: token}
  end

  test "accepte un JWT ES256 aligné sur auth-service (JWKS + kid)", %{token: token} do
    conn =
      :get
      |> conn("/api/v1/auth-check")
      |> put_req_header("authorization", "Bearer " <> token)
      |> Router.call([])

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "ok"
    assert body["sub"] == "user-123"
  end

  defp sign_es256_token(private_jwk, kid) do
    now = System.system_time(:second)

    claims = %{
      "sub" => "user-123",
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
