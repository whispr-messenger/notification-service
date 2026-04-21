defmodule WhisprNotificationsWeb.RouterTest do
  @moduledoc """
  Covers the alternate `/notification/api` scope kept for gateways that forward
  the full path without stripping the `/notification` prefix.
  """
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.Router

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "GET /notification/api/v1/health returns 200" do
    conn = :get |> conn("/notification/api/v1/health") |> Router.call([])
    assert conn.status == 200
  end

  test "GET /notification/api/settings/:id returns 200" do
    conn = :get |> conn("/notification/api/settings/#{unique_id("u")}") |> Router.call([])
    assert conn.status == 200
  end

  test "PUT /notification/api/settings/:id returns 204" do
    conn =
      :put
      |> conn("/notification/api/settings/#{unique_id("u")}", %{"foo" => "bar"})
      |> Router.call([])

    assert conn.status == 204
  end

  test "POST /notification/api/conversations/:id/mute returns 204" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :post
      |> conn("/notification/api/conversations/#{conv_id}/mute", %{"user_id" => user_id})
      |> Router.call([])

    assert conn.status == 204
  end

  test "DELETE /notification/api/conversations/:id/mute returns 204" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :delete
      |> conn("/notification/api/conversations/#{conv_id}/mute", %{"user_id" => user_id})
      |> Router.call([])

    assert conn.status == 204
  end

  test "GET /notification/api/v1/auth-check returns 401 without JWT" do
    conn = :get |> conn("/notification/api/v1/auth-check") |> Router.call([])
    assert conn.status == 401
  end
end
