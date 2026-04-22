defmodule WhisprNotificationsWeb.Plugs.CorsTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias WhisprNotificationsWeb.Plugs.Cors

  @opts Cors.init([])
  @allowed_origin "https://whispr-api.roadmvn.com"
  @disallowed_origin "https://evil.example.com"

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
end
