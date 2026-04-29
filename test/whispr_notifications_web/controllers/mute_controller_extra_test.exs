defmodule WhisprNotificationsWeb.MuteControllerExtraTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Conn, only: [assign: 3]
  import Plug.Test

  alias WhisprNotificationsWeb.MuteController

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "treats empty mute_until like absent — 204 falls through" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :post
      |> conn("/api/conversations/#{conv_id}/mute")
      |> assign(:jwt_sub, user_id)
      |> MuteController.mute(%{
        "conversation_id" => conv_id,
        "user_id" => user_id,
        "mute_until" => ""
      })

    assert conn.status == 204
  end
end
