defmodule WhisprNotifications.Test.AuthHelpers do
  @moduledoc """
  Test helpers for bypassing the `:jwt_authenticated` pipeline in controller
  and router tests.

  Call `AuthHelpers.setup_jwt/1` in a `setup` block to wire up a `JwksCache`
  backed by `ES256JwtFixtures`, and use `put_bearer/2` to attach a signed
  token to a `%Plug.Conn{}`.
  """

  import Plug.Conn, only: [put_req_header: 3]

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Test.ES256JwtFixtures

  @default_issuer "whispr-auth"
  @default_audience "whispr-notification"

  @doc """
  Starts a `JwksCache` with the primary test key and points the app
  config at it. Returns `%{token: token}` to merge into ExUnit context.

  Must be used together with `ExUnit.Callbacks.start_supervised!/1`,
  so the calling test module needs `use ExUnit.Case` (which imports it).
  """
  def setup_jwt(opts \\ []) do
    server = Keyword.get(opts, :server, unique_server_name())
    sub = Keyword.get(opts, :sub, "user-test")
    issuer = Keyword.get(opts, :issuer, @default_issuer)
    audience = Keyword.get(opts, :audience, @default_audience)

    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end

    original = Application.get_env(:whispr_notification, :jwt)

    Application.put_env(
      :whispr_notification,
      :jwt,
      jwks_url: "http://auth-service/auth/.well-known/jwks.json",
      issuer: issuer,
      audience: audience,
      allowed_algs: ["ES256"],
      jwks_refresh_interval_ms: 60_000,
      jwks_cache_server: server
    )

    ExUnit.Callbacks.start_supervised!(
      {JwksCache, [name: server, http_get_fun: http_get_fun]}
    )

    ExUnit.Callbacks.on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:whispr_notification, :jwt)
      else
        Application.put_env(:whispr_notification, :jwt, original)
      end
    end)

    %{token: sign_token(sub: sub, issuer: issuer, audience: audience)}
  end

  @doc """
  Adds an `Authorization: Bearer <token>` header to a `%Plug.Conn{}`.
  """
  def put_bearer(conn, token) when is_binary(token) do
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  @doc """
  Signs an ES256 JWT using the primary test private key.
  """
  def sign_token(opts \\ []) do
    sub = Keyword.get(opts, :sub, "user-test")
    issuer = Keyword.get(opts, :issuer, @default_issuer)
    audience = Keyword.get(opts, :audience, @default_audience)
    exp = Keyword.get(opts, :exp, System.system_time(:second) + 3600)

    claims = %{
      "sub" => sub,
      "iss" => issuer,
      "aud" => audience,
      "exp" => exp
    }

    {_, token} =
      ES256JwtFixtures.primary_private_jwk()
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => ES256JwtFixtures.primary_kid()}, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp unique_server_name do
    String.to_atom("jwks_cache_test_" <> Integer.to_string(System.unique_integer([:positive])))
  end
end
