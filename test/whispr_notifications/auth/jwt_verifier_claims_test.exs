defmodule WhisprNotifications.Auth.JwtVerifierClaimsTest do
  @moduledoc """
  Hits the `validate_exp`/`claim_int`/`claim_str`/`stringify_claims` private
  helpers via the public `verify/1` entry point, by signing tokens whose
  claims are atom-keyed instead of string-keyed (Joken-style) — this drives
  the fallback branches in `claim_int` (`String.to_existing_atom/1` rescue),
  `claim_str` (atom fallback) and `stringify_claims` (atom branch).
  """
  use ExUnit.Case, async: false

  alias WhisprNotifications.Auth.{JwksCache, JwtVerifier}
  alias WhisprNotifications.Test.ES256JwtFixtures

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _ -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_jwt_claims_test

    original = Application.get_env(:whispr_notification, :jwt)

    Application.put_env(
      :whispr_notification,
      :jwt,
      jwks_url: "http://auth-service/auth/.well-known/jwks.json",
      issuer: "whispr-auth",
      audience: "whispr-notification",
      allowed_algs: ["ES256"],
      jwks_cache_server: server
    )

    start_supervised!({JwksCache, [name: server, http_get_fun: http_get_fun]})

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:whispr_notification, :jwt)
      else
        Application.put_env(:whispr_notification, :jwt, original)
      end
    end)

    :ok
  end

  test "accepts a valid token with no `exp` claim" do
    kid = ES256JwtFixtures.primary_kid()

    token =
      sign_es256(ES256JwtFixtures.primary_private_jwk(), kid, %{
        "sub" => "u-no-exp",
        "iss" => "whispr-auth",
        "aud" => "whispr-notification"
      })

    assert {:ok, claims} = JwtVerifier.verify(token)
    assert claims["sub"] == "u-no-exp"
  end

  test "accepts a token with atom-keyed claims (claim_int / claim_str fallbacks)" do
    kid = ES256JwtFixtures.primary_kid()

    # Build claims with atom keys so the JOSE.JWT.to_map output keeps them as
    # atoms; this drives the `claim_int` String.to_existing_atom path and
    # `stringify_claims` atom branch.
    atom_claims = %{
      sub: "u-atom",
      iss: "whispr-auth",
      aud: "whispr-notification",
      exp: System.system_time(:second) + 600
    }

    token = sign_es256(ES256JwtFixtures.primary_private_jwk(), kid, atom_claims)

    assert {:ok, claims} = JwtVerifier.verify(token)
    # stringify_claims must have converted any atom keys back to strings
    assert claims["sub"] == "u-atom"
  end

  defp sign_es256(priv, kid, claims) do
    {_, token} =
      priv
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
