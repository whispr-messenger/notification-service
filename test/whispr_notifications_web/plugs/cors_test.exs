defmodule WhisprNotificationsWeb.Plugs.CorsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias WhisprNotificationsWeb.Plugs.Cors

  @opts Cors.init([])
  @env_key "CORS_ALLOWED_ORIGINS"
  @allowed_origin "https://whispr.test.local"
  @disallowed_origin "https://evil.example.com"

  setup do
    previous = System.get_env(@env_key)
    System.put_env(@env_key, @allowed_origin)

    on_exit(fn ->
      case previous do
        nil -> System.delete_env(@env_key)
        value -> System.put_env(@env_key, value)
      end
    end)

    :ok
  end

  test "adds CORS headers for allowed origin" do
    conn =
      :get
      |> conn("/api/v1/health")
      |> put_req_header("origin", @allowed_origin)
      |> Cors.call(@opts)

    assert get_resp_header(conn, "access-control-allow-origin") == [@allowed_origin]

    assert get_resp_header(conn, "access-control-allow-methods") == [
             "GET, POST, PUT, PATCH, DELETE, OPTIONS"
           ]

    assert get_resp_header(conn, "access-control-allow-headers") == [
             "authorization, content-type, accept"
           ]

    assert get_resp_header(conn, "access-control-max-age") == ["86400"]
    assert get_resp_header(conn, "vary") == ["Origin"]
  end

  test "does not add CORS headers for disallowed origin" do
    conn =
      :get
      |> conn("/api/v1/health")
      |> put_req_header("origin", @disallowed_origin)
      |> Cors.call(@opts)

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "does not add CORS headers when no origin header" do
    conn =
      :get
      |> conn("/api/v1/health")
      |> Cors.call(@opts)

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "OPTIONS request returns 204 and halts for allowed origin" do
    conn =
      :options
      |> conn("/api/v1/health")
      |> put_req_header("origin", @allowed_origin)
      |> Cors.call(@opts)

    assert conn.status == 204
    assert conn.halted == true
    assert get_resp_header(conn, "access-control-allow-origin") == [@allowed_origin]
  end

  test "OPTIONS request returns 204 and halts without CORS headers for disallowed origin" do
    conn =
      :options
      |> conn("/api/v1/health")
      |> put_req_header("origin", @disallowed_origin)
      |> Cors.call(@opts)

    assert conn.status == 204
    assert conn.halted == true
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  describe "fail-closed when CORS_ALLOWED_ORIGINS is unset" do
    setup do
      System.delete_env(@env_key)
      :ok
    end

    test "no CORS headers even for an origin that would otherwise be allowed" do
      conn =
        :get
        |> conn("/api/v1/health")
        |> put_req_header("origin", @allowed_origin)
        |> Cors.call(@opts)

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end

    test "OPTIONS request returns 204 and halts without CORS headers" do
      conn =
        :options
        |> conn("/api/v1/health")
        |> put_req_header("origin", @allowed_origin)
        |> Cors.call(@opts)

      assert conn.status == 204
      assert conn.halted == true
      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end

  describe "fail-closed when CORS_ALLOWED_ORIGINS is empty" do
    setup do
      System.put_env(@env_key, "")
      :ok
    end

    test "no CORS headers even for an origin that would otherwise be allowed" do
      conn =
        :get
        |> conn("/api/v1/health")
        |> put_req_header("origin", @allowed_origin)
        |> Cors.call(@opts)

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end
end
