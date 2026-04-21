defmodule WhisprNotifications.Preferences.ManagerTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Preferences.{Manager, UserSettings, ConversationSettings}
  alias WhisprNotifications.Test.NotificationFixtures

  describe "get_user_settings/1" do
    test "returns default UserSettings struct" do
      assert {:ok, %UserSettings{user_id: "u-1"}} = Manager.get_user_settings("u-1")
    end
  end

  describe "get_conversation_settings/2" do
    test "returns default ConversationSettings struct" do
      assert {:ok, %ConversationSettings{user_id: "u-1", conversation_id: "c-2"}} =
               Manager.get_conversation_settings("u-1", "c-2")
    end
  end

  describe "allowed_for_notification?/2" do
    test "returns true for a notification with default settings" do
      notif = NotificationFixtures.build_notification()
      assert Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "uses DateTime.utc_now/0 when no now is passed" do
      notif = NotificationFixtures.build_notification()
      assert Manager.allowed_for_notification?(notif)
    end
  end
end
