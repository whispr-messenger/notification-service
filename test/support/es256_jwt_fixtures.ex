defmodule WhisprNotifications.Test.ES256JwtFixtures do
  @moduledoc false

  # Clés P-256 statiques (tests uniquement). Évite JOSE.JWK.generate_key/1 qui casse sur OTP 26+ (ECPrivateKey ecPrivkeyVer1).

  @primary_private %{
    "kty" => "EC",
    "crv" => "P-256",
    "x" => "a2YAHLf4haxgkXZqd5l0qiLu9Mk08PjExKY5yXyg_nM",
    "y" => "5AgI7AoGg09e-b_7JNMk40tU1uQndUz6lb3DcJ1F2W0",
    "d" => "Zkby6A0zVH_IMVFOV58GEfHDSGu_q88ugXBIKjPHImo"
  }

  @other_private %{
    "kty" => "EC",
    "crv" => "P-256",
    "x" => "AL7v88nSupaRPdHwk_HxWTPZa9P3Uv8EJxTOPSRpwvk",
    "y" => "Y0D9i8VQHo-T0_1xdB2PeAwte6jwdqCmfZJEgsFIrt8",
    "d" => "0wwPUoaWYfrOAd_GpQWerQMm3kRNUkI6vvelvrLq08k"
  }

  @primary_kid "auth-service-test-key-1"

  def primary_kid, do: @primary_kid

  def primary_private_jwk, do: JOSE.JWK.from_map(@primary_private)

  def other_private_jwk, do: JOSE.JWK.from_map(@other_private)

  def primary_jwks_public_entry do
    @primary_private
    |> Map.delete("d")
    |> Map.merge(%{"kid" => @primary_kid, "use" => "sig", "alg" => "ES256"})
  end
end
