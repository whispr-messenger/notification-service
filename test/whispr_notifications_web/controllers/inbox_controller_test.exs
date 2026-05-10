defmodule WhisprNotificationsWeb.InboxControllerTest do
  use WhisprNotifications.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias WhisprNotifications.Auth.JwksCache
  alias WhisprNotifications.Inbox
  alias WhisprNotifications.Test.ES256JwtFixtures
  alias WhisprNotificationsWeb.Router

  @test_user "user-inbox-ctrl-test"

  setup do
    kid = ES256JwtFixtures.primary_kid()
    jwks_key = ES256JwtFixtures.primary_jwks_public_entry()
    payload = %{"keys" => [jwks_key]}
    http_get_fun = fn _url -> {:ok, %{status: 200, body: payload}} end

    Application.put_env(
      :whispr_notification,
      :jwt,
      jwks_url: "http://auth-service/auth/.well-known/jwks.json",
      issuer: "whispr-auth",
      audience: "whispr-notification",
      allowed_algs: ["ES256"],
      jwks_refresh_interval_ms: 60_000,
      jwks_cache_server: :jwks_cache_inbox_test
    )

    start_supervised!({JwksCache, [name: :jwks_cache_inbox_test, http_get_fun: http_get_fun]})

    token = sign_token(ES256JwtFixtures.primary_private_jwk(), kid, @test_user)
    {:ok, token: token}
  end

  describe "GET /api/v1/inbox" do
    test "sans token retourne 401" do
      conn = :get |> conn("/api/v1/inbox") |> Router.call([])
      assert conn.status == 401
    end

    test "retourne 200 avec une liste vide quand pas d'items", %{token: token} do
      conn =
        :get
        |> conn("/api/v1/inbox")
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["items"] == []
      assert body["unread_count"] == 0
    end

    test "retourne les items de l'utilisateur avec unread_count", %{token: token} do
      {:ok, _} = Inbox.insert(@test_user, "mention", %{"conv" => "c1"})
      {:ok, _} = Inbox.insert(@test_user, "reply", %{"conv" => "c2"})

      conn =
        :get
        |> conn("/api/v1/inbox")
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["items"]) == 2
      assert body["unread_count"] == 2

      item = hd(body["items"])
      assert Map.has_key?(item, "id")
      assert Map.has_key?(item, "event_type")
      assert Map.has_key?(item, "payload")
      assert Map.has_key?(item, "created_at")
    end

    test "respecte le parametre limit", %{token: token} do
      # insere plus d'items que le limit demande
      for i <- 1..5 do
        {:ok, _} = Inbox.insert(@test_user, "mention", %{"i" => i})
      end

      # Plug.Test.conn/3 avec map de params passe les query params via assigns
      conn =
        :get
        |> conn("/api/v1/inbox", %{"limit" => "2"})
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["items"]) == 2
    end
  end

  describe "POST /api/v1/inbox/mark-read" do
    test "sans token retourne 401" do
      conn =
        :post
        |> conn("/api/v1/inbox/mark-read", %{"all" => "true"})
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 401
    end

    test "mark-read avec all: true marque tous les items", %{token: token} do
      {:ok, _} = Inbox.insert(@test_user, "mention", %{})
      {:ok, _} = Inbox.insert(@test_user, "reply", %{})

      conn =
        :post
        |> conn("/api/v1/inbox/mark-read", %{"all" => true})
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["updated"] == 2
    end

    test "mark-read avec ids marque uniquement les items specifies", %{token: token} do
      {:ok, item1} = Inbox.insert(@test_user, "mention", %{})
      {:ok, _item2} = Inbox.insert(@test_user, "reply", %{})

      conn =
        :post
        |> conn("/api/v1/inbox/mark-read", %{"ids" => [item1.id]})
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["updated"] == 1
    end

    test "400 quand all et ids sont fournis ensemble", %{token: token} do
      {:ok, item} = Inbox.insert(@test_user, "mention", %{})

      conn =
        :post
        |> conn("/api/v1/inbox/mark-read", %{"all" => true, "ids" => [item.id]})
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "mutuellement exclusifs"
    end

    test "400 quand le corps est invalide (ni ids ni all)", %{token: token} do
      conn =
        :post
        |> conn("/api/v1/inbox/mark-read", %{"foo" => "bar"})
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> Router.call([])

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "requis"
    end
  end

  defp sign_token(private_jwk, kid, sub) do
    now = System.system_time(:second)

    claims = %{
      "sub" => sub,
      "iss" => "whispr-auth",
      "aud" => "whispr-notification",
      "exp" => now + 3600
    }

    {_, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
