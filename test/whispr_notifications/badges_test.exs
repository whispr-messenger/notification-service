defmodule WhisprNotifications.BadgesTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Badges
  alias WhisprNotifications.Workers.MessagingSubscriber

  describe "incr/decr/get" do
    test "get returns 0 for unknown user" do
      assert Badges.get("unknown-user") == 0
    end

    test "incr creates the row and returns the new count" do
      assert Badges.incr("u-1") == 1
      assert Badges.incr("u-1") == 2
      assert Badges.incr("u-1", 3) == 5
      assert Badges.get("u-1") == 5
    end

    test "decr never goes below 0" do
      Badges.incr("u-2", 2)
      assert Badges.decr("u-2") == 1
      assert Badges.decr("u-2", 5) == 0
      assert Badges.get("u-2") == 0
    end

    test "reset sets to 0" do
      Badges.incr("u-3", 7)
      assert Badges.reset("u-3") == 0
      assert Badges.get("u-3") == 0
    end
  end

  describe "MessagingSubscriber.process_message/2" do
    test "new_message with target_user_ids increments each" do
      :ok =
        MessagingSubscriber.process_message("whispr:messaging:new_message", %{
          "target_user_ids" => ["a", "b"]
        })

      assert Badges.get("a") == 1
      assert Badges.get("b") == 1
    end

    test "new_message with user_id fallback increments one" do
      :ok =
        MessagingSubscriber.process_message("whispr:messaging:new_message", %{
          "user_id" => "solo"
        })

      assert Badges.get("solo") == 1
    end

    test "message_read decrements the reader" do
      Badges.incr("reader", 3)

      :ok =
        MessagingSubscriber.process_message("whispr:messaging:message_read", %{
          "user_id" => "reader",
          "count" => 2
        })

      assert Badges.get("reader") == 1
    end
  end
end
