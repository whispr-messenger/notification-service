defmodule WhisprNotifications.Delivery.ApnsClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias WhisprNotifications.Delivery.ApnsClient
  alias WhisprNotifications.Test.NotificationFixtures

  setup do
    original = Application.get_env(:whispr_notification, :apns_push_fun)

    on_exit(fn ->
      if original do
        Application.put_env(:whispr_notification, :apns_push_fun, original)
      else
        Application.delete_env(:whispr_notification, :apns_push_fun)
      end
    end)

    device = NotificationFixtures.build_ios_device()

    payload = %{
      "aps" => %{
        "alert" => %{"title" => "Test", "body" => "Hello"},
        "sound" => "default"
      },
      "meta" => %{"notification_id" => "n1", "type" => "message"}
    }

    {:ok, device: device, payload: payload}
  end

  describe "send/2 success" do
    test "returns :ok when push function succeeds", %{device: device, payload: payload} do
      Application.put_env(:whispr_notification, :apns_push_fun, fn _d, _p -> :ok end)

      assert :ok == ApnsClient.send(device, payload)
    end

    test "logs success with device token", %{device: device, payload: payload} do
      Application.put_env(:whispr_notification, :apns_push_fun, fn _d, _p -> :ok end)

      log =
        capture_log(fn ->
          ApnsClient.send(device, payload)
        end)

      assert log =~ "APNS push succeeded"
    end
  end

  describe "send/2 errors" do
    test "returns {:error, :invalid_device_token}", %{device: device, payload: payload} do
      Application.put_env(:whispr_notification, :apns_push_fun, fn _d, _p ->
        {:error, :invalid_device_token}
      end)

      assert {:error, :invalid_device_token} == ApnsClient.send(device, payload)
    end

    test "returns {:error, :service_unavailable} on provider outage", %{
      device: device,
      payload: payload
    } do
      Application.put_env(:whispr_notification, :apns_push_fun, fn _d, _p ->
        {:error, :service_unavailable}
      end)

      assert {:error, :service_unavailable} == ApnsClient.send(device, payload)
    end

    test "returns {:error, :timeout} on push timeout", %{device: device, payload: payload} do
      Application.put_env(:whispr_notification, :apns_push_fun, fn _d, _p ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} == ApnsClient.send(device, payload)
    end

    test "logs error details on failure", %{device: device, payload: payload} do
      Application.put_env(:whispr_notification, :apns_push_fun, fn _d, _p ->
        {:error, :invalid_device_token}
      end)

      log =
        capture_log(fn ->
          ApnsClient.send(device, payload)
        end)

      assert log =~ "APNS push failed"
      assert log =~ "invalid_device_token"
    end
  end

  describe "send/2 default behaviour" do
    test "uses default push function when none configured", %{device: device, payload: payload} do
      Application.delete_env(:whispr_notification, :apns_push_fun)

      assert :ok == ApnsClient.send(device, payload)
    end
  end
end
