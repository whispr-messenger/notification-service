defmodule WhisprNotifications.Preferences.ManagerTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Preferences.{Manager, UserSettings, ConversationSettings}
  alias WhisprNotifications.Test.NotificationFixtures

  describe "get_user_settings/1" do
    test "returns default UserSettings struct" do
      assert {:ok, %UserSettings{user_id: "u-1"}} = Manager.get_user_settings("u-1")
    end

    test "returns a persisted UserSettings when one exists" do
      uid = "pref-mgr-user-" <> Integer.to_string(System.unique_integer([:positive]))
      {:ok, _} = Manager.update_user_settings(uid, %{"language" => "fr"})

      assert {:ok, %UserSettings{user_id: ^uid, language: "fr"}} = Manager.get_user_settings(uid)
    end
  end

  describe "get_conversation_settings/2" do
    test "returns default ConversationSettings struct" do
      assert {:ok, %ConversationSettings{user_id: "u-1", conversation_id: "c-2"}} =
               Manager.get_conversation_settings("u-1", "c-2")
    end

    test "returns an empty struct when conversation_id is nil" do
      assert {:ok, %ConversationSettings{user_id: "u-nil", conversation_id: nil}} =
               Manager.get_conversation_settings("u-nil", nil)
    end

    test "returns the persisted row when set_muted has stored one" do
      uid = "pref-mgr-u-" <> Integer.to_string(System.unique_integer([:positive]))
      cid = "pref-mgr-c-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, _} = Manager.set_muted(uid, cid, true)

      assert {:ok, %ConversationSettings{muted: true, user_id: ^uid, conversation_id: ^cid}} =
               Manager.get_conversation_settings(uid, cid)
    end
  end

  describe "update_user_settings/2" do
    test "inserts the row when no settings exist yet" do
      uid = "pref-mgr-insert-" <> Integer.to_string(System.unique_integer([:positive]))

      assert {:ok, %UserSettings{user_id: ^uid, language: "fr"}} =
               Manager.update_user_settings(uid, %{"language" => "fr"})
    end

    test "updates the existing row" do
      uid = "pref-mgr-update-" <> Integer.to_string(System.unique_integer([:positive]))
      {:ok, _} = Manager.update_user_settings(uid, %{"language" => "fr"})

      assert {:ok, %UserSettings{language: "en", message_push_enabled: false}} =
               Manager.update_user_settings(uid, %{
                 "language" => "en",
                 "message_push_enabled" => false
               })
    end

    test "accepts atom-keyed attrs" do
      uid = "pref-mgr-atom-" <> Integer.to_string(System.unique_integer([:positive]))

      assert {:ok, %UserSettings{language: "es"}} =
               Manager.update_user_settings(uid, %{language: "es"})
    end
  end

  describe "set_muted/4" do
    test "creates a conversation_settings row with muted=true" do
      uid = "pref-mgr-mute-" <> Integer.to_string(System.unique_integer([:positive]))
      cid = "pref-mgr-mute-c-" <> Integer.to_string(System.unique_integer([:positive]))

      assert {:ok, %ConversationSettings{muted: true}} = Manager.set_muted(uid, cid, true)
    end

    test "respects mute_until option when provided" do
      uid = "pref-mgr-until-" <> Integer.to_string(System.unique_integer([:positive]))
      cid = "pref-mgr-until-c-" <> Integer.to_string(System.unique_integer([:positive]))
      until = ~U[2099-01-01 00:00:00Z]

      assert {:ok, %ConversationSettings{muted: true, mute_until: ^until}} =
               Manager.set_muted(uid, cid, true, mute_until: until)
    end

    test "clears mute_until when unmuting" do
      uid = "pref-mgr-clear-" <> Integer.to_string(System.unique_integer([:positive]))
      cid = "pref-mgr-clear-c-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, _} = Manager.set_muted(uid, cid, true, mute_until: ~U[2099-01-01 00:00:00Z])

      assert {:ok, %ConversationSettings{muted: false, mute_until: nil}} =
               Manager.set_muted(uid, cid, false)
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

    test "returns false when the conversation is muted indefinitely" do
      uid = "pref-mgr-allow-" <> Integer.to_string(System.unique_integer([:positive]))
      cid = "pref-mgr-allow-c-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, _} = Manager.set_muted(uid, cid, true)

      notif =
        NotificationFixtures.build_notification(%{user_id: uid, conversation_id: cid})

      refute Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "returns true when conversation_id is nil even if other conv is muted" do
      uid = "pref-mgr-nil-" <> Integer.to_string(System.unique_integer([:positive]))
      other_cid = "other-c-" <> Integer.to_string(System.unique_integer([:positive]))
      {:ok, _} = Manager.set_muted(uid, other_cid, true)

      notif = NotificationFixtures.build_notification(%{user_id: uid, conversation_id: nil})

      assert Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "returns false when the user is in quiet hours" do
      uid = "pref-mgr-quiet-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, _} =
        Manager.update_user_settings(uid, %{
          "quiet_hours_start" => ~T[22:00:00],
          "quiet_hours_end" => ~T[07:00:00]
        })

      notif = NotificationFixtures.build_notification(%{user_id: uid, conversation_id: nil})

      refute Manager.allowed_for_notification?(notif, ~U[2026-01-01 23:00:00Z])
    end
  end
end
