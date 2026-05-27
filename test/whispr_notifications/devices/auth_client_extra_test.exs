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
    assert Device.platforms() == ~w(android ios web web_push)
  end

  test "platform_atom defaults to :android for unknown stored platforms" do
    # Bypass the changeset validation to plant a row with a legacy/unknown
    # platform string and confirm the AuthClient mapping degrades to :android
    # instead of raising. Required because the changeset only allows the
    # canonical three values, but historical rows may pre-date that constraint.
    user_id = "33333333-3333-4333-8333-0000000000ab"

    Repo.insert!(%Device{
      user_id: user_id,
      device_id: "legacy-1",
      fcm_token: "legacy-tok",
      platform: "blackberry",
      app_version: nil
    })

    {:ok, %DeviceCache{devices: devices}} = AuthClient.fetch_devices(user_id)
    assert Enum.any?(devices, fn d -> d.platform == :android and d.token == "legacy-tok" end)
  end
end
