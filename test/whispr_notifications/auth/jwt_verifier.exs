defmodule WhisprNotifications.Auth.JwtVerifierTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Auth.{JwksCache, JwtVerifier}
  alias WhisprNotifications.Test.ES256JwtFixtures

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end

    server = :jwks_cache_jwt_verifier_test

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

    :ok
  end

  test "verify/1 accepts token when kid matches JWKS" do
    kid = ES256JwtFixtures.primary_kid()
    token = sign_es256(ES256JwtFixtures.primary_private_jwk(), kid, %{"sub" => "u1"})
    assert {:ok, claims} = JwtVerifier.verify(token)
    assert claims["sub"] == "u1"
  end

  test "verify/1 rejects unknown kid" do
    token =
      sign_es256(
        ES256JwtFixtures.primary_private_jwk(),
        "not-in-jwks",
        %{"sub" => "u1"}
      )

    assert {:error, :unknown_kid} = JwtVerifier.verify(token)
  end

  test "verify/1 rejects token signed with another key (wrong signature for kid)" do
    kid = ES256JwtFixtures.primary_kid()
    token = sign_es256(ES256JwtFixtures.other_private_jwk(), kid, %{"sub" => "u1"})
    assert {:error, :invalid_signature} = JwtVerifier.verify(token)
  end

  defp sign_es256(priv, kid, claims) do
    now = System.system_time(:second)
    claims = Map.merge(%{"iss" => "whispr-auth", "aud" => "whispr-notification", "exp" => now + 3600}, claims)

    {_, token} =
      priv
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
