defmodule WhisprNotifications.Preferences.ManagerTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Preferences.{Manager, UserSettings, ConversationSettings}
  alias WhisprNotifications.Test.NotificationFixtures

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  describe "get_user_settings/1" do
    test "returns default UserSettings struct when no row exists" do
      uid = unique_id("u")
      assert {:ok, %UserSettings{user_id: ^uid}} = Manager.get_user_settings(uid)
    end

    test "returns a persisted UserSettings when one exists" do
      uid = unique_id("pref-mgr-user")
      {:ok, _} = Manager.update_user_settings(uid, %{"language" => "fr"})

      assert {:ok, %UserSettings{user_id: ^uid, language: "fr"}} = Manager.get_user_settings(uid)
    end
  end

  describe "get_conversation_settings/2" do
    test "returns default ConversationSettings struct" do
      uid = unique_id("u")
      cid = unique_id("c")

      assert {:ok, %ConversationSettings{user_id: ^uid, conversation_id: ^cid}} =
               Manager.get_conversation_settings(uid, cid)
    end

    test "returns an empty struct when conversation_id is nil" do
      uid = unique_id("u-nil")

      assert {:ok, %ConversationSettings{user_id: ^uid, conversation_id: nil}} =
               Manager.get_conversation_settings(uid, nil)
    end

    test "returns the persisted row when set_muted has stored one" do
      uid = unique_id("pref-mgr-u")
      cid = unique_id("pref-mgr-c")

      {:ok, _} = Manager.set_muted(uid, cid, true)

      assert {:ok, %ConversationSettings{muted: true, user_id: ^uid, conversation_id: ^cid}} =
               Manager.get_conversation_settings(uid, cid)
    end
  end

  describe "update_user_settings/2" do
    test "inserts the row when no settings exist yet" do
      uid = unique_id("pref-mgr-insert")

      assert {:ok, %UserSettings{user_id: ^uid, language: "fr"}} =
               Manager.update_user_settings(uid, %{"language" => "fr"})
    end

    test "updates the existing row" do
      uid = unique_id("pref-mgr-update")
      {:ok, _} = Manager.update_user_settings(uid, %{"language" => "fr"})

      assert {:ok, %UserSettings{language: "en", message_push_enabled: false}} =
               Manager.update_user_settings(uid, %{
                 "language" => "en",
                 "message_push_enabled" => false
               })
    end

    test "accepts atom-keyed attrs" do
      uid = unique_id("pref-mgr-atom")

      assert {:ok, %UserSettings{language: "es"}} =
               Manager.update_user_settings(uid, %{language: "es"})
    end

    test "returns a changeset error on invalid attrs" do
      uid = unique_id("pref-mgr-invalid")

      assert {:error, %Ecto.Changeset{valid?: false}} =
               Manager.update_user_settings(uid, %{"quiet_hours_start" => "not-a-time"})
    end
  end

  describe "set_muted/4" do
    test "creates a conversation_settings row with muted=true" do
      uid = unique_id("pref-mgr-mute")
      cid = unique_id("pref-mgr-mute-c")

      assert {:ok, %ConversationSettings{muted: true}} = Manager.set_muted(uid, cid, true)
    end

    test "respects mute_until option when provided" do
      uid = unique_id("pref-mgr-until")
      cid = unique_id("pref-mgr-until-c")
      until = ~U[2099-01-01 00:00:00Z]

      assert {:ok, %ConversationSettings{muted: true, mute_until: ^until}} =
               Manager.set_muted(uid, cid, true, mute_until: until)
    end

    test "clears mute_until when unmuting" do
      uid = unique_id("pref-mgr-clear")
      cid = unique_id("pref-mgr-clear-c")

      {:ok, _} = Manager.set_muted(uid, cid, true, mute_until: ~U[2099-01-01 00:00:00Z])

      assert {:ok, %ConversationSettings{muted: false, mute_until: nil}} =
               Manager.set_muted(uid, cid, false)
    end
  end

  describe "allowed_for_notification?/2" do
    test "returns true for a notification with default settings" do
      notif = NotificationFixtures.build_notification(%{user_id: unique_id("u")})
      assert Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "uses DateTime.utc_now/0 when no now is passed" do
      notif = NotificationFixtures.build_notification(%{user_id: unique_id("u")})
      assert Manager.allowed_for_notification?(notif)
    end

    test "returns false when the conversation is muted indefinitely" do
      uid = unique_id("pref-mgr-allow")
      cid = unique_id("pref-mgr-allow-c")

      {:ok, _} = Manager.set_muted(uid, cid, true)

      notif =
        NotificationFixtures.build_notification(%{user_id: uid, conversation_id: cid})

      refute Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "returns true when mute_until is in the past" do
      uid = unique_id("pref-mgr-past")
      cid = unique_id("pref-mgr-past-c")

      {:ok, _} = Manager.set_muted(uid, cid, true, mute_until: ~U[2020-01-01 00:00:00Z])

      notif =
        NotificationFixtures.build_notification(%{user_id: uid, conversation_id: cid})

      assert Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "returns true when conversation_id is nil even if another conv is muted" do
      uid = unique_id("pref-mgr-nil")
      other_cid = unique_id("other-c")
      {:ok, _} = Manager.set_muted(uid, other_cid, true)

      notif = NotificationFixtures.build_notification(%{user_id: uid, conversation_id: nil})

      assert Manager.allowed_for_notification?(notif, ~U[2026-01-01 10:00:00Z])
    end

    test "returns false when the user is in quiet hours" do
      uid = unique_id("pref-mgr-quiet")

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
