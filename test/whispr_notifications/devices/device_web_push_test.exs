defmodule WhisprNotifications.Devices.DeviceWebPushTest do
  @moduledoc """
  Tests du schema Device pour la plateforme web_push.
  """
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.{AuthClient, Device, DeviceCache}

  @user_id "web-push-user-001"

  # ----- changeset validations -----

  describe "Device.changeset/2 — web_push" do
    test "accepte platform web_push avec wp_p256dh et wp_auth" do
      attrs = %{
        user_id: @user_id,
        device_id: "browser-pwa-1",
        fcm_token: "https://fcm.googleapis.com/fcm/send/fake-endpoint",
        platform: "web_push",
        wp_p256dh: "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
        wp_auth: "n_auth_secret"
      }

      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
    end

    test "rejette platform web_push sans wp_p256dh" do
      attrs = %{
        user_id: @user_id,
        device_id: "browser-pwa-2",
        fcm_token: "https://example.com/push/endpoint",
        platform: "web_push",
        wp_auth: "n_auth_secret"
      }

      changeset = Device.changeset(%Device{}, attrs)
      refute changeset.valid?
      assert %{wp_p256dh: [_ | _]} = changeset.errors |> Enum.into(%{}, fn {k, v} -> {k, [v]} end)
    end

    test "rejette platform web_push sans wp_auth" do
      attrs = %{
        user_id: @user_id,
        device_id: "browser-pwa-3",
        fcm_token: "https://example.com/push/endpoint",
        platform: "web_push",
        wp_p256dh: "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c"
      }

      changeset = Device.changeset(%Device{}, attrs)
      refute changeset.valid?
      assert changeset.errors[:wp_auth] != nil
    end

    test "android ne requiert pas wp_p256dh ni wp_auth" do
      attrs = %{
        user_id: @user_id,
        device_id: "android-dev-1",
        fcm_token: "fcm-android-token",
        platform: "android"
      }

      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
    end

    test "rejette une platform inconnue" do
      attrs = %{
        user_id: @user_id,
        device_id: "unknown-dev",
        fcm_token: "some-token",
        platform: "desktop"
      }

      changeset = Device.changeset(%Device{}, attrs)
      refute changeset.valid?
      assert changeset.errors[:platform] != nil
    end
  end

  # ----- Devices.upsert + AuthClient.fetch_devices -----

  describe "Devices.upsert/1 + AuthClient pour web_push" do
    test "persiste un device web_push et le retrouve via AuthClient avec les clés VAPID" do
      {:ok, _device} =
        Devices.upsert(%{
          user_id: @user_id,
          device_id: "pwa-safari-ios",
          fcm_token: "https://web.push.apple.com/FAKE_ENDPOINT",
          platform: "web_push",
          wp_p256dh: "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
          wp_auth: "n_auth_secret_base64url"
        })

      assert {:ok, %DeviceCache{devices: [cached]}} = AuthClient.fetch_devices(@user_id)

      assert cached.platform == :web_push
      assert cached.token == "https://web.push.apple.com/FAKE_ENDPOINT"
      assert cached.wp_p256dh == "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c"
      assert cached.wp_auth == "n_auth_secret_base64url"
    end

    test "un device android n'a pas de clés wp dans le cache" do
      {:ok, _device} =
        Devices.upsert(%{
          user_id: @user_id,
          device_id: "android-test",
          fcm_token: "fcm-android-token-2",
          platform: "android"
        })

      assert {:ok, %DeviceCache{devices: devices}} = AuthClient.fetch_devices(@user_id)
      android = Enum.find(devices, &(&1.platform == :android))

      refute Map.has_key?(android, :wp_p256dh)
      refute Map.has_key?(android, :wp_auth)
    end
  end
end
