defmodule WhisprNotificationsWeb.Plugs.AuthenticateTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Plugs.Authenticate

  @opts Authenticate.init([])

  setup do
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    http_get_fun = fn _url -> {:ok, %{status: 200, body: %{"keys" => [jwks_key]}}} end
    server = :jwks_cache_plug_authn_test

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

  test "init/1 returns its opts" do
    assert Authenticate.init(foo: 1) == [foo: 1]
  end

  test "returns 401 when no Authorization header" do
    conn = :get |> conn("/") |> Authenticate.call(@opts)
    assert conn.status == 401
    assert conn.halted
    assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
  end

  test "returns 401 when Authorization header is malformed" do
    conn =
      :get
      |> conn("/")
      |> put_req_header("authorization", "Token abc")
      |> Authenticate.call(@opts)

    assert conn.status == 401
    assert conn.halted
  end

  test "returns 401 for invalid Bearer token" do
    conn =
      :get
      |> conn("/")
      |> put_req_header("authorization", "Bearer not-a-token")
      |> Authenticate.call(@opts)

    assert conn.status == 401
    assert conn.halted
  end

  test "assigns jwt_claims and jwt_sub for a valid token" do
    token =
      sign_token(ES256JwtFixtures.primary_private_jwk(), ES256JwtFixtures.primary_kid())

    conn =
      :get
      |> conn("/")
      |> put_req_header("authorization", "Bearer " <> token)
      |> Authenticate.call(@opts)

    refute conn.halted
    assert conn.assigns.jwt_sub == "user-authn-test"
    assert is_map(conn.assigns.jwt_claims)
  end

  defp sign_token(priv, kid) do
    now = System.system_time(:second)

    claims = %{
      "sub" => "user-authn-test",
      "iss" => "whispr-auth",
      "aud" => "whispr-notification",
      "exp" => now + 3600
    }

    {_, token} =
      priv
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
