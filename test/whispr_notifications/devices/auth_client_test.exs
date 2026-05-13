defmodule WhisprNotifications.Devices.AuthClientTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.{AuthClient, DeviceCache}

  @user_id "33333333-3333-4333-8333-000000000042"

  test "returns an empty DeviceCache when no device is registered" do
    assert {:ok, %DeviceCache{user_id: @user_id, devices: []}} =
             AuthClient.fetch_devices(@user_id)
  end

  test "returns the active devices for the user as a DeviceCache" do
    {:ok, android} =
      Devices.upsert(%{
        user_id: @user_id,
        device_id: "pixel",
        fcm_token: "android-tok",
        platform: "android",
        app_version: "1.0.0"
      })

    {:ok, ios} =
      Devices.upsert(%{
        user_id: @user_id,
        device_id: "iphone",
        fcm_token: "ios-tok",
        platform: "ios",
        app_version: "2.0.0"
      })

    assert {:ok, %DeviceCache{user_id: @user_id, devices: devices}} =
             AuthClient.fetch_devices(@user_id)

    by_token = Map.new(devices, &{&1.token, &1})

    assert by_token["android-tok"].platform == :android
    assert by_token["android-tok"].internal_id == android.id
    assert by_token["android-tok"].device_id == "pixel"

    assert by_token["ios-tok"].platform == :ios
    assert by_token["ios-tok"].internal_id == ios.id
  end

  test "uses configured APNS topic for iOS devices instead of app_version" do
    previous = Application.get_env(:whispr_notification, :apns)

    Application.put_env(:whispr_notification, :apns,
      enabled: false,
      default_topic: "com.anonymous.Whispr-Frontend"
    )

    try do
      {:ok, _ios} =
        Devices.upsert(%{
          user_id: @user_id,
          device_id: "iphone-topic",
          fcm_token: "ios-topic-tok",
          platform: "ios",
          app_version: "2.0.0"
        })

      assert {:ok, %DeviceCache{devices: devices}} = AuthClient.fetch_devices(@user_id)
      ios_device = Enum.find(devices, &(&1.token == "ios-topic-tok"))

      assert ios_device.app == "com.anonymous.Whispr-Frontend"
    after
      restore(:apns, previous)
    end
  end

  test "omits soft-deleted devices" do
    {:ok, alive} =
      Devices.upsert(%{
        user_id: @user_id,
        device_id: "alive",
        fcm_token: "tok-alive",
        platform: "android"
      })

    {:ok, zombie} =
      Devices.upsert(%{
        user_id: @user_id,
        device_id: "zombie",
        fcm_token: "tok-zombie",
        platform: "android"
      })

    {:ok, _} = Devices.soft_delete(zombie.id)

    {:ok, %DeviceCache{devices: devices}} = AuthClient.fetch_devices(@user_id)

    assert Enum.map(devices, & &1.internal_id) == [alive.id]
  end

  test "rejects non-binary / empty user_id" do
    assert {:error, :invalid_user_id} = AuthClient.fetch_devices(nil)
    assert {:error, :invalid_user_id} = AuthClient.fetch_devices("")
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, value), do: Application.put_env(:whispr_notification, key, value)
end
