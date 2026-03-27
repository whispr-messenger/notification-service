defmodule WhisprNotificationsWeb.JwtGuardIntegrationTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotificationsWeb.Router

  setup do
    kid = "kid-integration-test"
    secret = "test-secret-integration-1234567890"
    private_jwk = JOSE.JWK.from_oct(secret)
    payload = %{
      "keys" => [
        %{
          "kty" => "oct",
          "kid" => kid,
          "alg" => "HS256",
          "use" => "sig",
          "k" => Base.url_encode64(secret, padding: false)
        }
      ]
    }

    http_get_fun = fn _url ->
      {:ok, %{status: 200, body: payload}}
    end

    Application.put_env(
      :whispr_notification,
      :jwt,
      jwks_url: "http://auth-service/auth/.well-known/jwks.json",
      issuer: "whispr-auth",
      audience: "whispr-notification",
      allowed_algs: ["HS256"],
      jwks_refresh_interval_ms: 60_000,
      jwks_cache_server: :jwks_cache_integration_test
    )

    start_supervised!({JwksCache, [name: :jwks_cache_integration_test, http_get_fun: http_get_fun]})

    token = sign_token(private_jwk, kid)
    {:ok, token: token}
  end

  test "accepts a JWT signed with a key from JWKS", %{token: token} do
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

  defp sign_token(private_jwk, kid) do
    now = System.system_time(:second)

    claims = %{
      "sub" => "user-123",
      "iss" => "whispr-auth",
      "aud" => "whispr-notification",
      "exp" => now + 3600
    }

    {_, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
