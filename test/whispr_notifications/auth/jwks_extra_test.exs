defmodule WhisprNotifications.Auth.JwksExtraTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Auth.Jwks

  test "returns :bad_jwk and halts when JOSE.JWK.from raises" do
    # A key with the right shape (kid + kty=EC + crv=P-256) but missing the
    # `x`/`y` coordinates makes JOSE.JWK.from raise — that triggers the
    # rescue clause + the {:halt, {:error, reason}} branch in build_key_map.
    bad_key = %{
      "kid" => "broken",
      "kty" => "EC",
      "crv" => "P-256"
      # no x, no y → JOSE chokes when materialising the JWK
    }

    json = Jason.encode!(%{"keys" => [bad_key]})

    assert {:error, :bad_jwk} = Jwks.keys_from_json(json)
  end
end
