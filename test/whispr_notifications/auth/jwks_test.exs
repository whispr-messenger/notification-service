defmodule WhisprNotifications.Auth.JwksTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Auth.Jwks
  alias WhisprNotifications.Test.ES256JwtFixtures

  setup do
    original = Application.get_env(:whispr_notification, :jwks_http_get)

    on_exit(fn ->
      if original do
        Application.put_env(:whispr_notification, :jwks_http_get, original)
      else
        Application.delete_env(:whispr_notification, :jwks_http_get)
      end
    end)

    :ok
  end

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

  describe "fetch_keys/1" do
    test "returns key map on HTTP 200 with valid JWKS body" do
      jwks_body = %{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]}

      Application.put_env(:whispr_notification, :jwks_http_get, fn _url ->
        {:ok, %{status: 200, body: Jason.encode!(jwks_body)}}
      end)

      assert {:ok, map} = Jwks.fetch_keys("http://fake/jwks")
      assert Map.has_key?(map, ES256JwtFixtures.primary_kid())
    end

    test "handles pre-decoded map body from HTTP client" do
      jwks_body = %{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]}

      Application.put_env(:whispr_notification, :jwks_http_get, fn _url ->
        {:ok, %{status: 200, body: jwks_body}}
      end)

      assert {:ok, map} = Jwks.fetch_keys("http://fake/jwks")
      assert Map.has_key?(map, ES256JwtFixtures.primary_kid())
    end

    test "returns HTTP error tuple on non-200 status" do
      Application.put_env(:whispr_notification, :jwks_http_get, fn _url ->
        {:ok, %{status: 503, body: ""}}
      end)

      assert {:error, {:http, 503}} = Jwks.fetch_keys("http://fake/jwks")
    end

    test "returns error on HTTP client failure" do
      Application.put_env(:whispr_notification, :jwks_http_get, fn _url ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Jwks.fetch_keys("http://fake/jwks")
    end
  end
end
