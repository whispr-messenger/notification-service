defmodule WhisprNotifications.DevicesTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.Device

  @user_a "11111111-1111-4111-8111-000000000001"
  @user_b "22222222-2222-4222-8222-000000000002"

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        user_id: @user_a,
        device_id: "pixel-9",
        fcm_token: "tok-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower),
        platform: "android",
        app_version: "1.2.3"
      },
      overrides
    )
  end

  describe "upsert/1" do
    test "inserts a new device" do
      assert {:ok, %Device{id: id, user_id: @user_a}} = Devices.upsert(valid_attrs())
      assert is_binary(id)
    end

    test "replaces fcm_token / app_version on repeated upsert for the same (user, device)" do
      {:ok, first} =
        Devices.upsert(valid_attrs(%{fcm_token: "tok-first", app_version: "1.0.0"}))

      {:ok, second} =
        Devices.upsert(valid_attrs(%{fcm_token: "tok-second", app_version: "1.1.0"}))

      assert first.id == second.id
      assert second.fcm_token == "tok-second"
      assert second.app_version == "1.1.0"
      assert Repo.aggregate(Device, :count) == 1
    end

    test "rejects invalid platform" do
      assert {:error, changeset} = Devices.upsert(valid_attrs(%{platform: "wtf"}))
      assert {"is invalid", _} = Keyword.fetch!(changeset.errors, :platform)
    end
  end

  describe "list_active_for_user/1" do
    test "returns only the user's own non-deleted devices" do
      {:ok, d1} = Devices.upsert(valid_attrs(%{device_id: "d1"}))
      {:ok, _d2} = Devices.upsert(valid_attrs(%{user_id: @user_b, device_id: "d-other"}))
      {:ok, d3} = Devices.upsert(valid_attrs(%{device_id: "d3"}))

      {:ok, _} = Devices.soft_delete(d3.id)

      result = Devices.list_active_for_user(@user_a)
      ids = Enum.map(result, & &1.id) |> MapSet.new()

      assert MapSet.member?(ids, d1.id)
      refute MapSet.member?(ids, d3.id)
      assert length(result) == 1
    end
  end

  describe "soft_delete_by_user_device/2" do
    test "flags deleted_at and is idempotent" do
      {:ok, device} = Devices.upsert(valid_attrs(%{device_id: "dx"}))
      assert is_nil(device.deleted_at)

      assert :ok = Devices.soft_delete_by_user_device(@user_a, "dx")
      # idempotent
      assert :ok = Devices.soft_delete_by_user_device(@user_a, "dx")

      reloaded = Repo.get!(Device, device.id)
      assert not is_nil(reloaded.deleted_at)
    end

    test "returns :ok for unknown (user, device) pair" do
      assert :ok = Devices.soft_delete_by_user_device(@user_a, "does-not-exist")
    end
  end

  describe "mark_invalid/2" do
    test "soft-deletes and records the error code" do
      {:ok, device} = Devices.upsert(valid_attrs(%{fcm_token: "bad-token"}))

      assert :ok = Devices.mark_invalid("bad-token", "UNREGISTERED")

      reloaded = Repo.get!(Device, device.id)
      assert reloaded.last_error == "UNREGISTERED"
      assert not is_nil(reloaded.last_error_at)
      assert not is_nil(reloaded.deleted_at)
    end

    test "returns {:error, :not_found} when no active device matches the token" do
      assert {:error, :not_found} = Devices.mark_invalid("nope", "INVALID")
    end

    test "does not touch already soft-deleted rows" do
      {:ok, device} = Devices.upsert(valid_attrs(%{fcm_token: "dup-token"}))
      {:ok, _} = Devices.soft_delete(device.id)

      assert {:error, :not_found} = Devices.mark_invalid("dup-token", "UNREGISTERED")
    end
  end

  describe "list_invalidated_before/1 and count_by_status/0" do
    test "lists invalidated devices older than cutoff and counts statuses" do
      {:ok, active} = Devices.upsert(valid_attrs(%{device_id: "active"}))
      {:ok, _} = Devices.upsert(valid_attrs(%{device_id: "invalid-old", fcm_token: "old"}))
      {:ok, _} = Devices.upsert(valid_attrs(%{device_id: "invalid-recent", fcm_token: "recent"}))

      :ok = Devices.mark_invalid("old", "UNREGISTERED")
      :ok = Devices.mark_invalid("recent", "INVALID")

      # Backdate the "old" row so it falls before cutoff.
      forty_days_ago = DateTime.add(DateTime.utc_now(), -40, :day)

      {1, _} =
        from(d in Device, where: d.fcm_token == "old")
        |> Repo.update_all(set: [last_error_at: DateTime.truncate(forty_days_ago, :second)])

      cutoff = DateTime.add(DateTime.utc_now(), -30, :day)
      old_ones = Devices.list_invalidated_before(cutoff)

      assert length(old_ones) == 1
      assert hd(old_ones).fcm_token == "old"

      assert %{active: 1, invalid: 2} = Devices.count_by_status()

      # active device still listed
      assert Devices.list_active_for_user(@user_a) |> Enum.map(& &1.id) == [active.id]
    end
  end
end
