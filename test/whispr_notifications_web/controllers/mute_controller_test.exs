defmodule WhisprNotificationsWeb.MuteControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.MuteController
  alias WhisprNotificationsWeb.Router

  test "POST /api/conversations/:id/mute returns 204 when user_id is in body" do
    conn =
      :post
      |> conn("/api/conversations/conv-1/mute", %{"user_id" => "u-1"})
      |> Router.call([])

    assert conn.status == 204
  end

  test "MuteController.mute/2 returns 204 directly" do
    conn =
      :post
      |> conn("/api/conversations/conv-1/mute")
      |> MuteController.mute(%{"conversation_id" => "conv-1", "user_id" => "u-1"})

    assert conn.status == 204
  end

  test "MuteController.unmute/2 returns 204 directly" do
    conn =
      :delete
      |> conn("/api/conversations/conv-1/mute")
      |> MuteController.unmute(%{"conversation_id" => "conv-1", "user_id" => "u-1"})

    assert conn.status == 204
  end
end
