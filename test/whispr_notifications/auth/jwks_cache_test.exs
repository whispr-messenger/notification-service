defmodule WhisprNotifications.Auth.JwksCacheTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Test.ES256JwtFixtures

  test "charge le JWKS (HTTP mock) et résout les clés par kid" do
    kid = ES256JwtFixtures.primary_kid()
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()

    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_test

    start_supervised!(
      {JwksCache,
       [
         name: server,
         jwks_url: "http://auth-service/auth/.well-known/jwks.json",
         refresh_interval_ms: 60_000,
         http_get_fun: http_get_fun
       ]}
    )

    assert {:ok, _key} = JwksCache.get_key(kid, server)
    assert {:error, :unknown_kid} = JwksCache.get_key("missing-kid", server)
  end
end
