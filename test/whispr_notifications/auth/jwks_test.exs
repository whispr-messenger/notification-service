defmodule WhisprNotifications.Auth.JwksTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Auth.Jwks
  alias WhisprNotifications.Test.ES256JwtFixtures

  describe "keys_from_json/1" do
    test "parses a valid JWKS and indexes by kid" do
      json = Jason.encode!(%{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]})

      assert {:ok, map} = Jwks.keys_from_json(json)
      assert Map.has_key?(map, ES256JwtFixtures.primary_kid())
      assert %JOSE.JWK{} = map[ES256JwtFixtures.primary_kid()]
    end

    test "returns :invalid_jwks_shape when 'keys' is missing" do
      assert {:error, :invalid_jwks_shape} = Jwks.keys_from_json(Jason.encode!(%{}))
    end

    test "returns :invalid_json on malformed JSON" do
      assert {:error, :invalid_json} = Jwks.keys_from_json("not-json")
    end

    test "skips keys without a kid" do
      key = ES256JwtFixtures.primary_jwks_public_entry() |> Map.delete("kid")
      json = Jason.encode!(%{"keys" => [key]})

      assert {:ok, map} = Jwks.keys_from_json(json)
      assert map == %{}
    end

    test "skips keys with wrong curve/kty" do
      bad =
        ES256JwtFixtures.primary_jwks_public_entry()
        |> Map.put("crv", "P-384")

      json = Jason.encode!(%{"keys" => [bad]})

      assert {:ok, map} = Jwks.keys_from_json(json)
      assert map == %{}
    end
  end

  describe "fetch_keys/2" do
    test "parses keys from a 200 response whose body is a decoded map" do
      body = %{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]}
      http_get = fn _url -> {:ok, %{status: 200, body: body}} end

      assert {:ok, map} = Jwks.fetch_keys("http://auth/jwks", http_get)
      assert Map.has_key?(map, ES256JwtFixtures.primary_kid())
    end

    test "parses keys from a 200 response whose body is a JSON string" do
      body_json = Jason.encode!(%{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]})
      http_get = fn _url -> {:ok, %{status: 200, body: body_json}} end

      assert {:ok, map} = Jwks.fetch_keys("http://auth/jwks", http_get)
      assert Map.has_key?(map, ES256JwtFixtures.primary_kid())
    end

    test "returns {:http, status} on non-200 responses" do
      http_get = fn _ -> {:ok, %{status: 500}} end
      assert {:error, {:http, 500}} = Jwks.fetch_keys("http://auth/jwks", http_get)
    end

    test "bubbles up transport errors" do
      http_get = fn _ -> {:error, :econnrefused} end
      assert {:error, :econnrefused} = Jwks.fetch_keys("http://auth/jwks", http_get)
    end
  end
end
