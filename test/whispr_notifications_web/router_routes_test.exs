defmodule WhisprNotificationsWeb.RouterRoutesTest do
  @moduledoc """
  Hits the router scopes the existing `RouterTest` skips: the `GET/PUT
  /v1/settings` shorthands under `/api`, and the `/notification/api/v1/*`
  routes for `notifications`, `badge` and `devices` under the `:jwt_authenticated`
  pipeline. Every request lacks a JWT — we only assert the route matched and
  the auth plug returned 401, which is enough to mark the route line as
  covered.
  """
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.Router

  defp call(method, path, body \\ %{}) do
    method |> conn(path, body) |> Router.call([])
  end

  test "GET /api/v1/settings returns 401 without auth" do
    assert call(:get, "/api/v1/settings").status == 401
  end

  test "PUT /api/v1/settings returns 401 without auth" do
    assert call(:put, "/api/v1/settings", %{"foo" => "bar"}).status == 401
  end

  test "GET /api/v1/badge returns 401 without auth" do
    assert call(:get, "/api/v1/badge").status == 401
  end

  test "POST /api/v1/notifications returns 401 without auth" do
    assert call(:post, "/api/v1/notifications", %{}).status == 401
  end

  test "POST /api/v1/devices returns 401 without auth" do
    assert call(:post, "/api/v1/devices", %{}).status == 401
  end

  test "DELETE /api/v1/devices/:device_id returns 401 without auth" do
    assert call(:delete, "/api/v1/devices/abc").status == 401
  end

  test "GET /notification/api/v1/badge returns 401 without auth" do
    assert call(:get, "/notification/api/v1/badge").status == 401
  end

  test "POST /notification/api/v1/notifications returns 401 without auth" do
    assert call(:post, "/notification/api/v1/notifications", %{}).status == 401
  end

  test "GET /notification/api/v1/settings returns 401 without auth" do
    assert call(:get, "/notification/api/v1/settings").status == 401
  end

  test "PUT /notification/api/v1/settings returns 401 without auth" do
    assert call(:put, "/notification/api/v1/settings", %{"foo" => "bar"}).status == 401
  end

  test "POST /notification/api/v1/devices returns 401 without auth" do
    assert call(:post, "/notification/api/v1/devices", %{}).status == 401
  end

  test "DELETE /notification/api/v1/devices/:device_id returns 401 without auth" do
    assert call(:delete, "/notification/api/v1/devices/abc").status == 401
  end
end
