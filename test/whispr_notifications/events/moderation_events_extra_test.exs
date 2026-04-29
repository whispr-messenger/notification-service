defmodule WhisprNotifications.Events.ModerationEventsExtraTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Events.ModerationEvents

  describe "handle_sanction_applied/1 — every sanction_type variant" do
    test "kick" do
      assert {:ok, notif} =
               ModerationEvents.handle_sanction_applied(%{
                 "user_id" => "u-kick",
                 "sanction_type" => "kick",
                 "reason" => "noise"
               })

      assert notif.title == "You have been removed from a conversation"
    end

    test "warning" do
      assert {:ok, notif} =
               ModerationEvents.handle_sanction_applied(%{
                 "user_id" => "u-warning",
                 "sanction_type" => "warning"
               })

      assert notif.title == "You have received a warning"
      # Default reason kicks in when key is missing.
      assert notif.body =~ "Violation of community guidelines"
    end

    test "perm_ban" do
      assert {:ok, notif} =
               ModerationEvents.handle_sanction_applied(%{
                 "user_id" => "u-perm",
                 "sanction_type" => "perm_ban",
                 "reason" => "fraud"
               })

      assert notif.title == "Your account has been suspended"
    end
  end

  describe "log_result error branch" do
    test "logs and returns the {:error, :validation, _} 3-tuple from Notifications.create" do
      # No user_id → Notifications.create rejects with
      # {:error, :validation, [...]}, which routes through log_result/3's
      # error clause (not the success clause).
      assert {:error, :validation, errors} =
               ModerationEvents.handle_sanction_applied(%{
                 "sanction_type" => "mute",
                 "reason" => "no user id"
               })

      assert is_list(errors)
    end
  end
end
