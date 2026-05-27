defmodule WhisprNotifications.Delivery.BatchProcessorWebPushTest do
  @moduledoc """
  Tests BatchProcessor pour la clause :web_push.
  """
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Delivery.BatchProcessor
  alias WhisprNotifications.Devices
  alias WhisprNotifications.Test.{NotificationFixtures, SpyWebPushClient}

  @user_id "bp-web-push-user-001"

  setup do
    original_wp = Application.get_env(:whispr_notification, :web_push_client_mod)
    original_spy_pid = Application.get_env(:whispr_notification, :web_push_spy_pid)
    original_spy_resp = Application.get_env(:whispr_notification, :web_push_spy_response)

    Application.put_env(:whispr_notification, :web_push_client_mod, SpyWebPushClient)
    Application.put_env(:whispr_notification, :web_push_spy_pid, self())
    Application.delete_env(:whispr_notification, :web_push_spy_response)

    on_exit(fn ->
      restore(:web_push_client_mod, original_wp)
      restore(:web_push_spy_pid, original_spy_pid)
      restore(:web_push_spy_response, original_spy_resp)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, val), do: Application.put_env(:whispr_notification, key, val)

  defp build_web_push_device(overrides \\ %{}) do
    Map.merge(
      %{
        token: "https://web.push.apple.com/FAKE_ENDPOINT_#{:rand.uniform(9999)}",
        platform: :web_push,
        wp_p256dh: "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
        wp_auth: "n_auth_secret_base64url",
        device_id: "pwa-test-#{:rand.uniform(9999)}",
        internal_id: nil
      },
      overrides
    )
  end

  describe "deliver/2 — routage web_push" do
    test "appelle WebPushClient pour un device :web_push" do
      notif = NotificationFixtures.build_notification()
      wp_device = build_web_push_device()
      cache = NotificationFixtures.build_device_cache(devices: [wp_device])

      assert :ok == BatchProcessor.deliver(notif, cache)
      assert_receive {:web_push_send, %{platform: :web_push}, _payload}
    end

    test "n'appelle pas WebPushClient pour un device iOS" do
      notif = NotificationFixtures.build_notification()
      ios = NotificationFixtures.build_ios_device()
      cache = NotificationFixtures.build_device_cache(devices: [ios])

      BatchProcessor.deliver(notif, cache)
      refute_receive {:web_push_send, _, _}
    end

    test "gère endpoint_expired : soft-delete du device en base" do
      Application.put_env(
        :whispr_notification,
        :web_push_spy_response,
        {:error, :endpoint_expired}
      )

      {:ok, db_device} =
        Devices.upsert(%{
          user_id: @user_id,
          device_id: "pwa-expired",
          fcm_token: "https://web.push.apple.com/EXPIRED",
          platform: "web_push",
          wp_p256dh: "BGvNnV3tWG6V2MGGKWDBLQ4VmKG5z4z2v3Y4H5T5V5c",
          wp_auth: "n_auth_secret"
        })

      wp_device =
        build_web_push_device(%{
          token: "https://web.push.apple.com/EXPIRED",
          internal_id: db_device.id
        })

      cache = NotificationFixtures.build_device_cache(devices: [wp_device])
      notif = NotificationFixtures.build_notification(%{user_id: @user_id})

      assert :ok == BatchProcessor.deliver(notif, cache)

      # le device doit être soft-deleted
      assert [] == Devices.list_active_for_user(@user_id)
    end

    test "retourne :ok même si WebPushClient échoue avec :transient" do
      Application.put_env(:whispr_notification, :web_push_spy_response, {:error, :transient})

      notif = NotificationFixtures.build_notification()
      wp_device = build_web_push_device()
      cache = NotificationFixtures.build_device_cache(devices: [wp_device])

      assert :ok == BatchProcessor.deliver(notif, cache)
    end

    test "gère :not_configured sans erreur (dev local sans VAPID)" do
      Application.put_env(:whispr_notification, :web_push_spy_response, {:error, :not_configured})

      notif = NotificationFixtures.build_notification()
      wp_device = build_web_push_device()
      cache = NotificationFixtures.build_device_cache(devices: [wp_device])

      assert :ok == BatchProcessor.deliver(notif, cache)
    end
  end
end
