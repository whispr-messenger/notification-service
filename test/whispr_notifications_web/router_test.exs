defmodule WhisprNotificationsWeb.RouterTest do
  @moduledoc """
  Covers the alternate `/notification/api` scope kept for gateways that forward
  the full path without stripping the `/notification` prefix.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias WhisprNotifications.Test.AuthHelpers
  alias WhisprNotificationsWeb.{MuteController, Router}

  setup do
    AuthHelpers.setup_jwt()
  end

  test "GET /notification/api/v1/health returns 200" do
    conn = :get |> conn("/notification/api/v1/health") |> Router.call([])
    assert conn.status == 200
  end

  test "GET /notification/api/settings/:id returns 200", %{token: token} do
    conn =
      :get
      |> conn("/notification/api/settings/router-u-alt")
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 200
  end

  test "PUT /notification/api/settings/:id returns 200 with JSON body", %{token: token} do
    conn =
      :put
      |> conn("/notification/api/settings/router-u-alt", %{"foo" => "bar"})
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["user_id"] == "router-u-alt"
  end

  test "POST /notification/api/conversations/:id/mute returns 204", %{token: token} do
    conn =
      :post
      |> conn("/notification/api/conversations/router-conv-1/mute", %{"user_id" => "router-u-1"})
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 204
  end

  test "DELETE mute via controller directly (alt scope parity)" do
    conn =
      :delete
      |> conn("/notification/api/conversations/router-conv-2/mute")
      |> MuteController.unmute(%{
        "conversation_id" => "router-conv-2",
        "user_id" => "router-u-2"
      })

    assert conn.status == 204
  end

  test "GET /notification/api/v1/auth-check returns 401 without JWT" do
    conn = :get |> conn("/notification/api/v1/auth-check") |> Router.call([])
    assert conn.status == 401
  end
end
