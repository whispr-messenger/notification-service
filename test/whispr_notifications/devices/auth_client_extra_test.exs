defmodule WhisprNotifications.Devices.AuthClientExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.{AuthClient, Device, DeviceCache}

  test "maps web devices to platform: :web" do
    user_id = "33333333-3333-4333-8333-000000000099"

    {:ok, _} =
      Devices.upsert(%{
        user_id: user_id,
        device_id: "browser-1",
        fcm_token: "web-tok",
        platform: "web"
      })

    {:ok, %DeviceCache{devices: devices}} = AuthClient.fetch_devices(user_id)

    assert Enum.any?(devices, fn d -> d.platform == :web and d.token == "web-tok" end)
  end

  test "Device.platforms/0 returns the canonical list" do
    assert Device.platforms() == ~w(android ios web)
  end
end
