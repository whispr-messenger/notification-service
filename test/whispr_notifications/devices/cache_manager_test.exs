defmodule WhisprNotifications.Devices.CacheManagerTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Devices.{CacheManager, DeviceCache}

  describe "get_cache/1" do
    test "lazily fetches a user's cache via AuthClient when absent" do
      assert {:ok, %DeviceCache{user_id: "cm-user-1", devices: []}} =
               CacheManager.get_cache("cm-user-1")
    end

    test "returns the same cache on subsequent calls (cached)" do
      {:ok, first} = CacheManager.get_cache("cm-user-2")
      {:ok, second} = CacheManager.get_cache("cm-user-2")

      assert first == second
    end
  end

  describe "refresh_cache/1" do
    test "returns :ok and updates the state asynchronously" do
      assert :ok = CacheManager.refresh_cache("cm-user-3")

      assert {:ok, %DeviceCache{user_id: "cm-user-3"}} =
               CacheManager.get_cache("cm-user-3")
    end
  end
end
