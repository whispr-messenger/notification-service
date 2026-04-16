defmodule WhisprNotifications.Notifications.NotificationTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Notifications.Notification

  describe "new/1" do
    test "generates an id and created_at when not provided" do
      notif =
        Notification.new(%{
          user_id: "u-1",
          type: :message,
          title: "t",
          body: "b",
          context: %{}
        })

      assert is_binary(notif.id)
      assert %DateTime{} = notif.created_at
      assert notif.user_id == "u-1"
      assert notif.type == :message
    end

    test "keeps explicit id and created_at" do
      dt = ~U[2026-01-01 00:00:00Z]

      notif =
        Notification.new(%{
          id: "fixed-id",
          user_id: "u-1",
          type: :system,
          title: "t",
          body: "b",
          context: %{},
          created_at: dt
        })

      assert notif.id == "fixed-id"
      assert notif.created_at == dt
    end

    test "raises when required keys are missing" do
      assert_raise ArgumentError, fn ->
        Notification.new(%{user_id: "u-1"})
      end
    end
  end

  describe "mark_read/2" do
    test "sets read_at to the given datetime" do
      notif =
        Notification.new(%{
          user_id: "u-1",
          type: :message,
          title: "t",
          body: "b",
          context: %{}
        })

      at = ~U[2026-01-02 10:00:00Z]
      updated = Notification.mark_read(notif, at)

      assert updated.read_at == at
    end

    test "defaults to DateTime.utc_now/0 when not given" do
      notif =
        Notification.new(%{
          user_id: "u-1",
          type: :message,
          title: "t",
          body: "b",
          context: %{}
        })

      updated = Notification.mark_read(notif)
      assert %DateTime{} = updated.read_at
    end
  end
end
