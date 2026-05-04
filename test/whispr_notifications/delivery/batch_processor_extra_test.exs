defmodule WhisprNotifications.Delivery.BatchProcessorExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Delivery.BatchProcessor
  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.Device
  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotifications.Test.NotificationFixtures

  setup do
    original_apns = Application.get_env(:whispr_notification, :apns_client_mod)
    original_fcm = Application.get_env(:whispr_notification, :fcm_client_mod)
    original_spy_pid = Application.get_env(:whispr_notification, :apns_spy_pid)
    original_spy_resp = Application.get_env(:whispr_notification, :apns_spy_response)

    Application.put_env(
      :whispr_notification,
      :apns_client_mod,
      WhisprNotifications.Test.SpyApnsClient
    )

    Application.put_env(
      :whispr_notification,
      :fcm_client_mod,
      WhisprNotifications.Test.SpyFcmClient
    )

    Application.put_env(:whispr_notification, :apns_spy_pid, self())

    on_exit(fn ->
      restore(:apns_client_mod, original_apns)
      restore(:fcm_client_mod, original_fcm)
      restore(:apns_spy_pid, original_spy_pid)
      restore(:apns_spy_response, original_spy_resp)
      Application.delete_env(:whispr_notification, :fcm_spy_response)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, val), do: Application.put_env(:whispr_notification, key, val)

  test "iOS device with invalid APNS token is soft-deleted" do
    Application.put_env(:whispr_notification, :apns_spy_response, {:error, :token_invalid})

    {:ok, device_row} =
      Devices.upsert(%{
        user_id: "user-apns-invalid",
        device_id: "iphone-bad",
        fcm_token: "ios-bad-token",
        platform: "ios"
      })

    notif = NotificationFixtures.build_notification()
    ios = NotificationFixtures.build_ios_device(%{token: "ios-bad-token"})
    cache = NotificationFixtures.build_device_cache(devices: [ios])

    assert :ok == BatchProcessor.deliver(notif, cache)

    reloaded = Repo.get!(Device, device_row.id)
    assert reloaded.deleted_at != nil
    assert reloaded.last_error == "INVALID"
  end

  test "device with empty/nil token is delivered without crashing" do
    # When the FCM client returns :token_invalid and the device has no usable
    # token in its struct, soft_delete_invalid/2 must hit its catch-all clause
    # (the second function head, line 83) without touching the DB.
    Application.put_env(:whispr_notification, :fcm_spy_response, {:error, :token_invalid})

    notif = NotificationFixtures.build_notification()
    android = NotificationFixtures.build_android_device(%{token: nil})
    cache = NotificationFixtures.build_device_cache(devices: [android])

    assert :ok == BatchProcessor.deliver(notif, cache)
  end

  test "deliver/2 with a notif missing user_id falls back to a nil badge" do
    # Notification.new/1 enforces user_id, so we build the struct directly to
    # exercise the `current_badge(nil) -> nil` branch.
    notif = struct!(Notification, %{
      id: Ecto.UUID.generate(),
      user_id: nil,
      type: :system,
      title: "x",
      body: "y",
      context: %{},
      metadata: %{},
      created_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    cache = NotificationFixtures.build_device_cache()

    assert :ok == BatchProcessor.deliver(notif, cache)
  end
end
