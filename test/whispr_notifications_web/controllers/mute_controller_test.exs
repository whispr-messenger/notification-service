defmodule WhisprNotificationsWeb.MuteControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias WhisprNotifications.Test.AuthHelpers
  alias WhisprNotificationsWeb.{MuteController, Router}

  setup do
    AuthHelpers.setup_jwt()
  end

  test "POST /api/conversations/:id/mute returns 204 when user_id is in body", %{token: token} do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-1/mute", %{"user_id" => "mute-ctrl-u-1"})
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 204
  end

  test "MuteController.mute/2 returns 204 directly" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-2/mute")
      |> MuteController.mute(%{
        "conversation_id" => "mute-ctrl-conv-2",
        "user_id" => "mute-ctrl-u-2"
      })

    assert conn.status == 204
  end

  test "MuteController.unmute/2 returns 204 directly" do
    conn =
      :delete
      |> conn("/api/conversations/mute-ctrl-conv-3/mute")
      |> MuteController.unmute(%{
        "conversation_id" => "mute-ctrl-conv-3",
        "user_id" => "mute-ctrl-u-3"
      })

    assert conn.status == 204
  end

  test "MuteController.mute/2 accepts a valid ISO8601 mute_until" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-4/mute")
      |> MuteController.mute(%{
        "conversation_id" => "mute-ctrl-conv-4",
        "user_id" => "mute-ctrl-u-4",
        "mute_until" => "2099-12-31T23:59:59Z"
      })

    assert conn.status == 204
  end

  test "MuteController.mute/2 returns 400 when user_id cannot be resolved" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-5/mute")
      |> MuteController.mute(%{"conversation_id" => "mute-ctrl-conv-5"})

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body) == %{"errors" => %{"user_id" => ["is required"]}}
  end

  test "MuteController.mute/2 returns 400 when user_id is an empty string" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-6/mute")
      |> MuteController.mute(%{
        "conversation_id" => "mute-ctrl-conv-6",
        "user_id" => ""
      })

    assert conn.status == 400
  end

  test "MuteController.mute/2 returns 400 on invalid ISO8601 mute_until" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-7/mute")
      |> MuteController.mute(%{
        "conversation_id" => "mute-ctrl-conv-7",
        "user_id" => "mute-ctrl-u-7",
        "mute_until" => "not-a-date"
      })

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body) == %{"errors" => %{"mute_until" => ["must be ISO8601"]}}
  end

  test "MuteController.mute/2 returns 400 when mute_until is not a string" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-8/mute")
      |> MuteController.mute(%{
        "conversation_id" => "mute-ctrl-conv-8",
        "user_id" => "mute-ctrl-u-8",
        "mute_until" => 12_345
      })

    assert conn.status == 400
  end

  test "MuteController.unmute/2 returns 400 when user_id is missing" do
    conn =
      :delete
      |> conn("/api/conversations/mute-ctrl-conv-9/mute")
      |> MuteController.unmute(%{"conversation_id" => "mute-ctrl-conv-9"})

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body) == %{"errors" => %{"user_id" => ["is required"]}}
  end

  test "MuteController.mute/2 treats a blank mute_until as none (204)" do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-10/mute")
      |> MuteController.mute(%{
        "conversation_id" => "mute-ctrl-conv-10",
        "user_id" => "mute-ctrl-u-10",
        "mute_until" => ""
      })

    assert conn.status == 204
  end

  test "MuteController.mute/2 returns 422 when Manager returns a changeset error" do
    conn =
      :post
      |> conn("/api/conversations/%20/mute")
      |> MuteController.mute(%{
        "conversation_id" => "",
        "user_id" => "mute-ctrl-u-11"
      })

    assert conn.status == 422
    decoded = Jason.decode!(conn.resp_body)
    assert Map.has_key?(decoded["errors"], "conversation_id")
  end

  test "MuteController.unmute/2 returns 422 when Manager returns a changeset error" do
    conn =
      :delete
      |> conn("/api/conversations/%20/mute")
      |> MuteController.unmute(%{
        "conversation_id" => "",
        "user_id" => "mute-ctrl-u-12"
      })

    assert conn.status == 422
    decoded = Jason.decode!(conn.resp_body)
    assert Map.has_key?(decoded["errors"], "conversation_id")
  end

  test "POST /api/conversations/:id/mute falls back to jwt_sub when no user_id in body", %{
    token: token
  } do
    conn =
      :post
      |> conn("/api/conversations/mute-ctrl-conv-fallback/mute")
      |> AuthHelpers.put_bearer(token)
      |> Router.call([])

    assert conn.status == 204
  end
end
