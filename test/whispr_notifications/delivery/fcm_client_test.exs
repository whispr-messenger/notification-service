defmodule WhisprNotifications.Delivery.FcmClientTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Delivery.FcmClient

  test "send/2 returns :ok with any device/payload" do
    device = %{token: "fcm-token", platform: :android, app: nil}
    payload = %{notification: %{title: "t", body: "b"}, data: %{}}

    assert :ok = FcmClient.send(device, payload)
  end
end
