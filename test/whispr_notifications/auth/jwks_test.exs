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
end
