defmodule WhisprNotifications.Auth.JwtVerifierExtraTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Auth.{JwksCache, JwtVerifier}
  alias WhisprNotifications.Test.ES256JwtFixtures

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_jwt_verifier_extra_test

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

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:whispr_notification, :jwt)
      else
        Application.put_env(:whispr_notification, :jwt, original)
      end
    end)

    :ok
  end

  test "rejects malformed token header" do
    assert {:error, :invalid_header} = JwtVerifier.verify("not-a-jwt")
  end

  test "rejects expired tokens" do
    kid = ES256JwtFixtures.primary_kid()

    token =
      sign_es256(ES256JwtFixtures.primary_private_jwk(), kid, %{
        "sub" => "u",
        "exp" => 1
      })

    assert {:error, :expired} = JwtVerifier.verify(token)
  end

  test "rejects wrong issuer" do
    kid = ES256JwtFixtures.primary_kid()

    token =
      sign_es256(ES256JwtFixtures.primary_private_jwk(), kid, %{
        "sub" => "u",
        "iss" => "someone-else"
      })

    assert {:error, :invalid_issuer} = JwtVerifier.verify(token)
  end

  test "rejects wrong audience" do
    kid = ES256JwtFixtures.primary_kid()

    token =
      sign_es256(ES256JwtFixtures.primary_private_jwk(), kid, %{
        "sub" => "u",
        "aud" => "other-service"
      })

    assert {:error, :invalid_audience} = JwtVerifier.verify(token)
  end

  test "rejects unsupported algorithms" do
    # Build a token where header alg is not in allowed list.
    header =
      %{"alg" => "HS256", "kid" => ES256JwtFixtures.primary_kid()}
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    claims = %{"sub" => "u"} |> Jason.encode!() |> Base.url_encode64(padding: false)
    fake_sig = Base.url_encode64("sig", padding: false)

    token = Enum.join([header, claims, fake_sig], ".")

    assert {:error, :unsupported_alg} = JwtVerifier.verify(token)
  end

  defp sign_es256(priv, kid, claims) do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{"iss" => "whispr-auth", "aud" => "whispr-notification", "exp" => now + 3600},
        claims
      )

    {_, token} =
      priv
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
