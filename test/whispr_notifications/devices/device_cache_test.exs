defmodule WhisprNotifications.Devices.DeviceCacheTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Devices.DeviceCache

  describe "add_device/2" do
    test "adds a device to an empty cache" do
      cache = %DeviceCache{user_id: "u-1", devices: []}
      device = %{token: "tok-1", platform: :ios, app: nil}

      updated = DeviceCache.add_device(cache, device)

      assert updated.devices == [device]
      assert updated.user_id == "u-1"
    end

    test "appends a device when token is new" do
      existing = %{token: "tok-1", platform: :ios, app: nil}
      new_one = %{token: "tok-2", platform: :android, app: nil}
      cache = %DeviceCache{user_id: "u-1", devices: [existing]}

      updated = DeviceCache.add_device(cache, new_one)

      assert updated.devices == [existing, new_one]
    end

    test "deduplicates by token when re-adding the same token" do
      old = %{token: "tok-1", platform: :ios, app: "old-app"}
      new = %{token: "tok-1", platform: :ios, app: "new-app"}
      cache = %DeviceCache{user_id: "u-1", devices: [old]}

      updated = DeviceCache.add_device(cache, new)

      assert length(updated.devices) == 1
      assert hd(updated.devices).app == "new-app"
    end
  end

  describe "remove_device/2" do
    test "removes a device by token" do
      a = %{token: "tok-a", platform: :ios, app: nil}
      b = %{token: "tok-b", platform: :android, app: nil}
      cache = %DeviceCache{user_id: "u-1", devices: [a, b]}

      updated = DeviceCache.remove_device(cache, "tok-a")

      assert updated.devices == [b]
    end

    test "is a no-op when token does not exist" do
      a = %{token: "tok-a", platform: :ios, app: nil}
      cache = %DeviceCache{user_id: "u-1", devices: [a]}

      updated = DeviceCache.remove_device(cache, "unknown")

      assert updated.devices == [a]
    end

    test "works on empty cache" do
      cache = %DeviceCache{user_id: "u-1", devices: []}
      assert DeviceCache.remove_device(cache, "tok") == cache
    end
  end
end
