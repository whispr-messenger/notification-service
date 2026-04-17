defmodule WhisprNotifications.Notifications.HistoryTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Notifications.History
  alias WhisprNotifications.Test.NotificationFixtures

  describe "save/1" do
    test "returns :ok for a valid notification" do
      notif = NotificationFixtures.build_notification()
      assert :ok == History.save(notif)
    end
  end

  describe "mark_read/2" do
    test "returns :ok" do
      assert :ok == History.mark_read("notif-id", DateTime.utc_now())
    end
  end

  describe "list_for_user/1" do
    test "returns empty list" do
      assert [] == History.list_for_user("user-1")
    end
  end
end
