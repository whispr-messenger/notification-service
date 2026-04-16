defmodule WhisprNotifications.Devices.AuthClientTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Devices.{AuthClient, DeviceCache}

  test "fetch_devices/1 returns an empty DeviceCache for the given user" do
    assert {:ok, %DeviceCache{user_id: "user-42", devices: []}} =
             AuthClient.fetch_devices("user-42")
  end
end
