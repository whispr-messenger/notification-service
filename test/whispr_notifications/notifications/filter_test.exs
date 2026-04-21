defmodule WhisprNotifications.Notifications.FilterTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Notifications.Filter
  alias WhisprNotifications.Test.NotificationFixtures

  describe "should_send?/2" do
    test "returns true for a default notification" do
      notif = NotificationFixtures.build_notification()
      assert Filter.should_send?(notif, ~U[2026-01-01 12:00:00Z])
    end

    test "returns true when called without a now argument" do
      notif = NotificationFixtures.build_notification()
      assert Filter.should_send?(notif)
    end
  end
end
