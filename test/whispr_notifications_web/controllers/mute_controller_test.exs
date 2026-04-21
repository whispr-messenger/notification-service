defmodule WhisprNotificationsWeb.MuteControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Conn, only: [assign: 3]
  import Plug.Test

  alias WhisprNotificationsWeb.MuteController

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  # /mute routes sit behind :jwt_authenticated (WHISPR-1028). Unit tests
  # drive the controller directly; router-level auth wiring is covered by
  # jwt_guard_integration_test.

  test "mute/2 returns 204 when user_id is in params" do
    conv_id = unique_id("conv")
    user_id = unique_id("u")

    conn =
      :post
      |> conn("/api/conversations/#{conv_id}/mute")
      |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => user_id})

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

  describe "mute/2 error branches" do
    test "returns 400 when user_id is missing and no JWT sub is assigned" do
      conv_id = unique_id("conv")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.mute(%{"conversation_id" => conv_id})

      assert conn.status == 400
      assert %{"errors" => %{"user_id" => ["is required"]}} = Jason.decode!(conn.resp_body)
    end

    test "returns 400 when user_id is an empty string" do
      conv_id = unique_id("conv")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => ""})

      assert conn.status == 400
      assert %{"errors" => %{"user_id" => ["is required"]}} = Jason.decode!(conn.resp_body)
    end

    test "returns 400 when mute_until is not an ISO8601 string" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.mute(%{
          "conversation_id" => conv_id,
          "user_id" => user_id,
          "mute_until" => "not-a-date"
        })

      assert conn.status == 400
      assert %{"errors" => %{"mute_until" => ["must be ISO8601"]}} = Jason.decode!(conn.resp_body)
    end

    test "returns 400 when mute_until is a non-string value" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.mute(%{
          "conversation_id" => conv_id,
          "user_id" => user_id,
          "mute_until" => 12_345
        })

      assert conn.status == 400
      assert %{"errors" => %{"mute_until" => ["must be ISO8601"]}} = Jason.decode!(conn.resp_body)
    end

    test "accepts a valid ISO8601 mute_until and returns 204" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.mute(%{
          "conversation_id" => conv_id,
          "user_id" => user_id,
          "mute_until" => "2030-01-01T00:00:00Z"
        })

      assert conn.status == 204
    end
  end

  describe "mute/2 jwt fallback and changeset errors" do
    test "falls back to conn.assigns.jwt_sub when user_id is absent from params" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> assign(:jwt_sub, jwt_user)
        |> MuteController.mute(%{"conversation_id" => conv_id})

      assert conn.status == 204
    end

    test "returns 422 when Manager returns a changeset error (blank conversation_id)" do
      user_id = unique_id("u")

      conn =
        :post
        |> conn("/api/conversations//mute")
        |> MuteController.mute(%{"conversation_id" => "", "user_id" => user_id})

      assert conn.status == 422
      decoded = Jason.decode!(conn.resp_body)
      assert Map.has_key?(decoded["errors"], "conversation_id")
    end
  end

  describe "unmute/2 error branches" do
    test "returns 400 when user_id is missing and no JWT sub is assigned" do
      conv_id = unique_id("conv")

      conn =
        :delete
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.unmute(%{"conversation_id" => conv_id})

      assert conn.status == 400
      assert %{"errors" => %{"user_id" => ["is required"]}} = Jason.decode!(conn.resp_body)
    end

    test "returns 400 when user_id is an empty string" do
      conv_id = unique_id("conv")

      conn =
        :delete
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.unmute(%{"conversation_id" => conv_id, "user_id" => ""})

      assert conn.status == 400
      assert %{"errors" => %{"user_id" => ["is required"]}} = Jason.decode!(conn.resp_body)
    end

    test "falls back to conn.assigns.jwt_sub when user_id is absent from params" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")

      conn =
        :delete
        |> conn("/api/conversations/#{conv_id}/mute")
        |> assign(:jwt_sub, jwt_user)
        |> MuteController.unmute(%{"conversation_id" => conv_id})

      assert conn.status == 204
    end

    test "returns 422 when Manager returns a changeset error (blank conversation_id)" do
      user_id = unique_id("u")

      conn =
        :delete
        |> conn("/api/conversations//mute")
        |> MuteController.unmute(%{"conversation_id" => "", "user_id" => user_id})

      assert conn.status == 422
      decoded = Jason.decode!(conn.resp_body)
      assert Map.has_key?(decoded["errors"], "conversation_id")
    end
  end
end
