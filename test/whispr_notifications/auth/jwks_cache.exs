defmodule WhisprNotifications.Auth.JwksCacheTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Auth.JwksCache

  test "loads JWKS from HTTP and resolves keys by kid" do
    kid = "kid-cache-test"
    secret = "test-secret-jwks-cache-1234567890"
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

    server = :jwks_cache_test

    start_supervised!(
      {JwksCache,
       [name: server, jwks_url: "http://auth-service/auth/.well-known/jwks.json", refresh_interval_ms: 60_000, http_get_fun: http_get_fun]}
    )

    assert {:ok, _key} = JwksCache.get_key(kid, server)
    assert {:error, :unknown_kid} = JwksCache.get_key("missing-kid", server)
  end
end
