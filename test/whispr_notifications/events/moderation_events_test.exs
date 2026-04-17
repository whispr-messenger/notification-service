defmodule WhisprNotifications.Events.ModerationEventsTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Events.ModerationEvents

  describe "handle_report_created/1" do
    test "creates notification for a report" do
      payload = %{
        "report_id" => "report-123",
        "reporter_id" => "user-1",
        "reported_user_id" => "user-2",
        "category" => "harassment"
      }

      assert {:ok, notif} = ModerationEvents.handle_report_created(payload)
      assert notif.type == :system
      assert notif.title == "New moderation report"
      assert notif.body =~ "harassment"
      assert notif.user_id == "admin"
      assert notif.context["event"] == "report_created"
      assert notif.context["report_id"] == "report-123"
    end
  end

  describe "handle_sanction_applied/1" do
    test "creates mute notification" do
      payload = %{
        "user_id" => "user-2",
        "sanction_type" => "mute",
        "reason" => "Spamming",
        "expires_at" => "2026-04-15T00:00:00Z"
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_applied(payload)
      assert notif.title == "You have been muted"
      assert notif.body =~ "Spamming"
      assert notif.body =~ "Expires:"
      assert notif.user_id == "user-2"
    end

    test "creates temp_ban notification without expiry" do
      payload = %{
        "user_id" => "user-3",
        "sanction_type" => "temp_ban",
        "reason" => nil,
        "expires_at" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_applied(payload)
      assert notif.title == "Your account has been temporarily suspended"
      assert notif.body =~ "Violation of community guidelines"
      refute notif.body =~ "Expires:"
    end

    test "creates notification for unknown sanction type" do
      payload = %{
        "user_id" => "user-4",
        "sanction_type" => "unknown_type",
        "reason" => "Test",
        "expires_at" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_applied(payload)
      assert notif.title == "Moderation action taken"
    end

    test "creates kick notification" do
      payload = %{
        "user_id" => "user-k",
        "sanction_type" => "kick",
        "reason" => "Rude",
        "expires_at" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_applied(payload)
      assert notif.title == "You have been removed from a conversation"
    end

    test "creates warning notification" do
      payload = %{
        "user_id" => "user-w",
        "sanction_type" => "warning",
        "reason" => "First strike",
        "expires_at" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_applied(payload)
      assert notif.title == "You have received a warning"
    end

    test "creates perm_ban notification" do
      payload = %{
        "user_id" => "user-p",
        "sanction_type" => "perm_ban",
        "reason" => "Repeated violations",
        "expires_at" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_applied(payload)
      assert notif.title == "Your account has been suspended"
    end
  end

  describe "handle_sanction_lifted/1" do
    test "creates sanction lifted notification" do
      payload = %{
        "user_id" => "user-2",
        "sanction_id" => "sanction-456"
      }

      assert {:ok, notif} = ModerationEvents.handle_sanction_lifted(payload)
      assert notif.title == "Sanction lifted"
      assert notif.user_id == "user-2"
      assert notif.context["sanction_id"] == "sanction-456"
    end
  end

  describe "handle_appeal_created/1" do
    test "creates appeal notification for admins" do
      payload = %{
        "appeal_id" => "appeal-789",
        "user_id" => "user-5",
        "sanction_id" => "sanction-456"
      }

      assert {:ok, notif} = ModerationEvents.handle_appeal_created(payload)
      assert notif.title == "New appeal submitted"
      assert notif.user_id == "admin"
      assert notif.context["appeal_id"] == "appeal-789"
    end
  end

  describe "handle_appeal_resolved/1" do
    test "creates accepted appeal notification" do
      payload = %{
        "appeal_id" => "appeal-789",
        "user_id" => "user-5",
        "status" => "accepted",
        "reviewer_notes" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_appeal_resolved(payload)
      assert notif.title == "Appeal accepted"
      assert notif.body =~ "accepted"
      assert notif.user_id == "user-5"
    end

    test "creates rejected appeal notification with reviewer notes" do
      payload = %{
        "appeal_id" => "appeal-789",
        "user_id" => "user-5",
        "status" => "rejected",
        "reviewer_notes" => "Insufficient evidence"
      }

      assert {:ok, notif} = ModerationEvents.handle_appeal_resolved(payload)
      assert notif.title == "Appeal rejected"
      assert notif.body =~ "Insufficient evidence"
    end

    test "creates generic appeal notification for unknown status" do
      payload = %{
        "appeal_id" => "appeal-789",
        "user_id" => "user-5",
        "status" => "pending",
        "reviewer_notes" => nil
      }

      assert {:ok, notif} = ModerationEvents.handle_appeal_resolved(payload)
      assert notif.title == "Appeal update"
    end
  end

  describe "handle_threshold_warning/1" do
    test "creates threshold warning notification" do
      payload = %{
        "reported_user_id" => "user-6",
        "threshold_level" => "high",
        "report_count" => 8
      }

      assert {:ok, notif} = ModerationEvents.handle_threshold_warning(payload)
      assert notif.title == "User approaching auto-sanction"
      assert notif.body =~ "8"
      assert notif.body =~ "high"
      assert notif.user_id == "admin"
    end
  end
end
