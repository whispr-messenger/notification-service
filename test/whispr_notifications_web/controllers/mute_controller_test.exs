defmodule WhisprNotificationsWeb.MuteControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.MuteController
  alias WhisprNotificationsWeb.Router

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "POST /api/conversations/:id/mute returns 204 when user_id is in body" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :post
      |> conn("/api/conversations/#{conv_id}/mute", %{"user_id" => user_id})
      |> Router.call([])

    assert conn.status == 204
  end

  test "MuteController.mute/2 returns 204 directly" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :post
      |> conn("/api/conversations/#{conv_id}/mute")
      |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => user_id})

    assert conn.status == 204
  end

  test "MuteController.unmute/2 returns 204 directly" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :delete
      |> conn("/api/conversations/#{conv_id}/mute")
      |> MuteController.unmute(%{"conversation_id" => conv_id, "user_id" => user_id})

    assert conn.status == 204
  end
end
