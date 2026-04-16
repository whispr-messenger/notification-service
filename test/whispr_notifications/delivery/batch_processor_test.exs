defmodule WhisprNotifications.Delivery.BatchProcessorTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Delivery.BatchProcessor
  alias WhisprNotifications.Test.NotificationFixtures

  setup do
    original_apns = Application.get_env(:whispr_notification, :apns_client_mod)
    original_fcm = Application.get_env(:whispr_notification, :fcm_client_mod)
    original_spy_pid = Application.get_env(:whispr_notification, :apns_spy_pid)
    original_spy_resp = Application.get_env(:whispr_notification, :apns_spy_response)
    original_fcm_pid = Application.get_env(:whispr_notification, :fcm_spy_pid)

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
    Application.put_env(:whispr_notification, :fcm_spy_pid, self())
    Application.delete_env(:whispr_notification, :apns_spy_response)

    on_exit(fn ->
      restore(:apns_client_mod, original_apns)
      restore(:fcm_client_mod, original_fcm)
      restore(:apns_spy_pid, original_spy_pid)
      restore(:apns_spy_response, original_spy_resp)
      restore(:fcm_spy_pid, original_fcm_pid)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, val), do: Application.put_env(:whispr_notification, key, val)

  describe "deliver/2 APNS routing" do
    test "sends APNS payload to each iOS device" do
      notif = NotificationFixtures.build_notification()
      d1 = NotificationFixtures.build_ios_device(%{token: "tok-1"})
      d2 = NotificationFixtures.build_ios_device(%{token: "tok-2"})
      cache = NotificationFixtures.build_device_cache(devices: [d1, d2])

      assert :ok == BatchProcessor.deliver(notif, cache)

      assert_receive {:apns_send, %{token: "tok-1"}, _payload}
      assert_receive {:apns_send, %{token: "tok-2"}, _payload}
    end

    test "formats payload as APNS before sending" do
      notif = NotificationFixtures.build_notification(%{title: "Hey", body: "World"})
      cache = NotificationFixtures.build_device_cache()

      BatchProcessor.deliver(notif, cache)

      assert_receive {:apns_send, _device, payload}
      assert %{"aps" => %{"alert" => %{"title" => "Hey", "body" => "World"}}} = payload
      assert payload["aps"]["sound"] == "default"
    end

    test "does not call ApnsClient for android devices" do
      notif = NotificationFixtures.build_notification()
      android = NotificationFixtures.build_android_device()
      cache = NotificationFixtures.build_device_cache(devices: [android])

      BatchProcessor.deliver(notif, cache)

      refute_receive {:apns_send, _, _}
      assert_receive {:fcm_send, _, _}
    end

    test "handles mixed platform device list" do
      notif = NotificationFixtures.build_notification()

      ios = NotificationFixtures.build_ios_device(%{token: "ios-tok"})
      android = NotificationFixtures.build_android_device(%{token: "android-tok"})
      web = NotificationFixtures.build_web_device(%{token: "web-tok"})
      cache = NotificationFixtures.build_device_cache(devices: [ios, android, web])

      BatchProcessor.deliver(notif, cache)

      assert_receive {:apns_send, %{token: "ios-tok"}, _}
      assert_receive {:fcm_send, %{token: "android-tok"}, _}
      refute_receive {:apns_send, %{token: "android-tok"}, _}
      refute_receive {:apns_send, %{token: "web-tok"}, _}
    end

    test "returns :ok even when sends fail" do
      Application.put_env(
        :whispr_notification,
        :apns_spy_response,
        {:error, :service_unavailable}
      )

      notif = NotificationFixtures.build_notification()
      cache = NotificationFixtures.build_device_cache()

      assert :ok == BatchProcessor.deliver(notif, cache)
    end
  end

  describe "deliver/2 retry behaviour" do
    test "retries on APNS failure" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Application.put_env(:whispr_notification, :apns_spy_response, fn ->
        call = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
        if call == 0, do: {:error, :service_unavailable}, else: :ok
      end)

      notif = NotificationFixtures.build_notification()
      cache = NotificationFixtures.build_device_cache()

      BatchProcessor.deliver(notif, cache)

      assert_receive {:apns_send, _, _}
      assert_receive {:apns_send, _, _}

      Agent.stop(counter)
    end

    test "stops retrying after max retries (3)" do
      Application.put_env(
        :whispr_notification,
        :apns_spy_response,
        {:error, :service_unavailable}
      )

      notif = NotificationFixtures.build_notification()
      cache = NotificationFixtures.build_device_cache()

      BatchProcessor.deliver(notif, cache)

      # 1 initial + 3 retries = 4 calls
      for _ <- 1..4 do
        assert_receive {:apns_send, _, _}
      end

      refute_receive {:apns_send, _, _}
    end
  end
end
