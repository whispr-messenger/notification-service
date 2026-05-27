defmodule WhisprNotificationsWeb.MuteControllerTest do
  use WhisprNotifications.DataCase, async: true
  import Plug.Conn, only: [assign: 3]
  import Plug.Test

  alias WhisprNotificationsWeb.MuteController

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  # /mute routes sit behind :jwt_authenticated (WHISPR-1028). Unit tests
  # drive the controller directly; router-level auth wiring is covered by
  # jwt_guard_integration_test.
  #
  # Authorization contract (WHISPR security audit §8):
  #   - body user_id == jwt_sub → 204
  #   - body user_id absent (or "") → 204, falls back to jwt_sub
  #   - body user_id != jwt_sub → 403
  #   - jwt_sub missing (plug bypassed) → 403

  defp build_conn(verb, conv_id, jwt_sub) do
    verb
    |> conn("/api/conversations/#{conv_id}/mute")
    |> assign(:jwt_sub, jwt_sub)
  end

  describe "mute/2 — authorization" do
    test "returns 204 when body user_id matches jwt_sub" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :post
        |> build_conn(conv_id, user_id)
        |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => user_id})

      assert conn.status == 204
    end

    test "falls back to jwt_sub when body user_id is absent" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")

      conn =
        :post
        |> build_conn(conv_id, jwt_user)
        |> MuteController.mute(%{"conversation_id" => conv_id})

      assert conn.status == 204
    end

    test "treats empty-string user_id like missing and falls back to jwt_sub" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")

      conn =
        :post
        |> build_conn(conv_id, jwt_user)
        |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => ""})

      assert conn.status == 204
    end

    test "returns 403 when body user_id differs from jwt_sub" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")
      victim = unique_id("victim")

      conn =
        :post
        |> build_conn(conv_id, jwt_user)
        |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => victim})

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
    end

    test "returns 403 when jwt_sub is missing even if body user_id is present" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :post
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => user_id})

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
    end
  end

  describe "mute/2 — mute_until and changeset errors" do
    test "returns 400 when mute_until is not an ISO8601 string" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :post
        |> build_conn(conv_id, user_id)
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
        |> build_conn(conv_id, user_id)
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
        |> build_conn(conv_id, user_id)
        |> MuteController.mute(%{
          "conversation_id" => conv_id,
          "user_id" => user_id,
          "mute_until" => "2030-01-01T00:00:00Z"
        })

      assert conn.status == 204
    end

    test "returns 422 when Manager returns a changeset error (blank conversation_id)" do
      user_id = unique_id("u")

      conn =
        :post
        |> conn("/api/conversations//mute")
        |> assign(:jwt_sub, user_id)
        |> MuteController.mute(%{"conversation_id" => "", "user_id" => user_id})

      assert conn.status == 422
      decoded = Jason.decode!(conn.resp_body)
      assert Map.has_key?(decoded["errors"], "conversation_id")
    end
  end

  describe "index/2 — list muted conversations" do
    test "returns empty list when user has no muted conversations" do
      user_id = unique_id("u")

      conn =
        :get
        |> conn("/api/conversations/mutes")
        |> assign(:jwt_sub, user_id)
        |> MuteController.index(%{})

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"mutes" => []}
    end

    test "returns muted conversations after POST mute" do
      user_id = unique_id("u")
      conv_id = unique_id("conv")

      :post
      |> build_conn(conv_id, user_id)
      |> MuteController.mute(%{"conversation_id" => conv_id, "user_id" => user_id})

      conn =
        :get
        |> conn("/api/conversations/mutes")
        |> assign(:jwt_sub, user_id)
        |> MuteController.index(%{})

      assert conn.status == 200
      assert %{"mutes" => [entry]} = Jason.decode!(conn.resp_body)
      assert entry["conversation_id"] == conv_id
      assert entry["muted"] == true
      assert entry["mute_until"] == nil
    end

    test "filters out expired mute_until entries" do
      user_id = unique_id("u")
      past_conv = unique_id("conv-past")
      future_conv = unique_id("conv-future")

      past_iso =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.to_iso8601()

      future_iso =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.to_iso8601()

      :post
      |> build_conn(past_conv, user_id)
      |> MuteController.mute(%{
        "conversation_id" => past_conv,
        "user_id" => user_id,
        "mute_until" => past_iso
      })

      :post
      |> build_conn(future_conv, user_id)
      |> MuteController.mute(%{
        "conversation_id" => future_conv,
        "user_id" => user_id,
        "mute_until" => future_iso
      })

      conn =
        :get
        |> conn("/api/conversations/mutes")
        |> assign(:jwt_sub, user_id)
        |> MuteController.index(%{})

      assert conn.status == 200
      assert %{"mutes" => mutes} = Jason.decode!(conn.resp_body)
      conv_ids = Enum.map(mutes, & &1["conversation_id"])
      assert future_conv in conv_ids
      refute past_conv in conv_ids
    end

    test "returns 403 when jwt_sub is missing" do
      conn =
        :get
        |> conn("/api/conversations/mutes")
        |> MuteController.index(%{})

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
    end

    test "does not leak mutes from other users" do
      user_a = unique_id("u-a")
      user_b = unique_id("u-b")
      conv_a = unique_id("conv-a")

      :post
      |> build_conn(conv_a, user_a)
      |> MuteController.mute(%{"conversation_id" => conv_a, "user_id" => user_a})

      conn =
        :get
        |> conn("/api/conversations/mutes")
        |> assign(:jwt_sub, user_b)
        |> MuteController.index(%{})

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"mutes" => []}
    end
  end

  describe "unmute/2 — authorization" do
    test "returns 204 when body user_id matches jwt_sub" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :delete
        |> build_conn(conv_id, user_id)
        |> MuteController.unmute(%{"conversation_id" => conv_id, "user_id" => user_id})

      assert conn.status == 204
    end

    test "falls back to jwt_sub when body user_id is absent" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")

      conn =
        :delete
        |> build_conn(conv_id, jwt_user)
        |> MuteController.unmute(%{"conversation_id" => conv_id})

      assert conn.status == 204
    end

    test "treats empty-string user_id like missing and falls back to jwt_sub" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")

      conn =
        :delete
        |> build_conn(conv_id, jwt_user)
        |> MuteController.unmute(%{"conversation_id" => conv_id, "user_id" => ""})

      assert conn.status == 204
    end

    test "returns 403 when body user_id differs from jwt_sub" do
      conv_id = unique_id("conv")
      jwt_user = unique_id("jwt-sub")
      victim = unique_id("victim")

      conn =
        :delete
        |> build_conn(conv_id, jwt_user)
        |> MuteController.unmute(%{"conversation_id" => conv_id, "user_id" => victim})

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
    end

    test "returns 403 when jwt_sub is missing even if body user_id is present" do
      conv_id = unique_id("conv")
      user_id = unique_id("u")

      conn =
        :delete
        |> conn("/api/conversations/#{conv_id}/mute")
        |> MuteController.unmute(%{"conversation_id" => conv_id, "user_id" => user_id})

      assert conn.status == 403
    end

    test "returns 422 when Manager returns a changeset error (blank conversation_id)" do
      user_id = unique_id("u")

      conn =
        :delete
        |> conn("/api/conversations//mute")
        |> assign(:jwt_sub, user_id)
        |> MuteController.unmute(%{"conversation_id" => "", "user_id" => user_id})

      assert conn.status == 422
      decoded = Jason.decode!(conn.resp_body)
      assert Map.has_key?(decoded["errors"], "conversation_id")
    end
  end
end
