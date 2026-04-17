defmodule WhisprNotificationsWeb.RouterTest do
  @moduledoc """
  Covers the alternate `/notification/api` scope kept for gateways that forward
  the full path without stripping the `/notification` prefix.
  """
  use ExUnit.Case, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.{MuteController, Router}

  test "GET /notification/api/v1/health returns 200" do
    conn = :get |> conn("/notification/api/v1/health") |> Router.call([])
    assert conn.status == 200
  end

  test "GET /notification/api/settings/:id returns 200" do
    conn = :get |> conn("/notification/api/settings/u-alt") |> Router.call([])
    assert conn.status == 200
  end

  test "PUT /notification/api/settings/:id returns 204" do
    conn =
      :put
      |> conn("/notification/api/settings/u-alt", %{"foo" => "bar"})
      |> Router.call([])

    assert conn.status == 204
  end

  test "POST /notification/api/conversations/:id/mute returns 204" do
    conn =
      :post
      |> conn("/notification/api/conversations/conv-1/mute", %{"user_id" => "u-1"})
      |> Router.call([])

    assert conn.status == 204
  end

  test "DELETE mute via controller directly (alt scope parity)" do
    conn =
      :delete
      |> conn("/notification/api/conversations/conv-1/mute")
      |> MuteController.unmute(%{"conversation_id" => "conv-1", "user_id" => "u-1"})

    assert conn.status == 204
  end

  test "GET /notification/api/v1/auth-check returns 401 without JWT" do
    conn = :get |> conn("/notification/api/v1/auth-check") |> Router.call([])
    assert conn.status == 401
  end
end
