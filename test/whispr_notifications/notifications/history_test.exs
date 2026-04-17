defmodule WhisprNotifications.Notifications.HistoryTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Notifications.{History, Notification}
  alias WhisprNotifications.Test.NotificationFixtures

  describe "save/1" do
    test "returns :ok for a valid notification" do
      notif = NotificationFixtures.build_notification()
      assert :ok == History.save(notif)
    end

    test "returns {:error, changeset} when required fields are missing" do
      invalid = %Notification{
        id: Ecto.UUID.generate(),
        created_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      assert {:error, %Ecto.Changeset{valid?: false}} = History.save(invalid)
    end
  end

  describe "mark_read/2" do
    test "returns :ok" do
      notif = NotificationFixtures.build_notification()
      assert :ok == History.save(notif)
      assert :ok == History.mark_read(notif.id, DateTime.utc_now())
    end

    test "returns {:error, :not_found} when id does not exist" do
      assert {:error, :not_found} ==
               History.mark_read(Ecto.UUID.generate(), DateTime.utc_now())
    end
  end

  describe "list_for_user/2" do
    test "returns empty list for an unknown user" do
      assert [] == History.list_for_user("user-with-no-notifs")
    end

    test "honours :limit and :offset options" do
      uid = "history-list-" <> Integer.to_string(System.unique_integer([:positive]))

      for i <- 1..3 do
        :ok =
          History.save(
            NotificationFixtures.build_notification(%{
              id: Ecto.UUID.generate(),
              user_id: uid,
              title: "n-#{i}"
            })
          )
      end

      assert length(History.list_for_user(uid, limit: 2)) == 2
      assert length(History.list_for_user(uid, limit: 10, offset: 1)) == 2
    end
  end
end
