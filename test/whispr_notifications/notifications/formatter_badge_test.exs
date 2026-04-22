defmodule WhisprNotifications.Notifications.FormatterBadgeTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Notifications.{Formatter, Notification}

  defp notif do
    Notification.new(%{
      user_id: "u-1",
      type: :message,
      title: "T",
      body: "B",
      context: %{}
    })
  end

  test "ios payload injects aps.badge when provided" do
    payload = Formatter.to_platform_payload(notif(), :ios, 4)
    assert get_in(payload, ["aps", "badge"]) == 4
  end

  test "android payload injects notification.badge and data.badge" do
    payload = Formatter.to_platform_payload(notif(), :android, 7)
    assert payload.notification.badge == 7
    assert payload.data["badge"] == "7"
  end

  test "no badge key when nil is passed" do
    payload = Formatter.to_platform_payload(notif(), :ios, nil)
    refute Map.has_key?(payload["aps"], "badge")
  end

  test "backward compatible two-arity call" do
    payload = Formatter.to_platform_payload(notif(), :ios)
    refute Map.has_key?(payload["aps"], "badge")
  end
end
