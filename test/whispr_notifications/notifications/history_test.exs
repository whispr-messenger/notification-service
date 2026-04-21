defmodule WhisprNotifications.Notifications.HistoryTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Notifications.History
  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotifications.Repo
  alias WhisprNotifications.Test.NotificationFixtures

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  describe "save/1" do
    test "returns :ok for a valid notification" do
      notif = NotificationFixtures.build_notification(%{id: unique_id("notif")})
      assert :ok == History.save(notif)
    end

    test "is idempotent on conflicting id (on_conflict: :nothing)" do
      id = unique_id("notif")
      notif = NotificationFixtures.build_notification(%{id: id, user_id: unique_id("u")})

      assert :ok == History.save(notif)
      assert :ok == History.save(notif)
    end
  end

  describe "mark_read/2" do
    test "returns :ok for a non-existent id (no-op)" do
      assert :ok == History.mark_read(unique_id("missing"), DateTime.utc_now())
    end

    test "persists read_at on an existing notification" do
      user_id = unique_id("u")
      notif = NotificationFixtures.build_notification(%{id: unique_id("notif"), user_id: user_id})
      :ok = History.save(notif)

      at = DateTime.utc_now() |> DateTime.truncate(:second)
      assert :ok == History.mark_read(notif.id, at)

      reloaded = Repo.get!(Notification, notif.id)
      assert reloaded.read_at == at
    end
  end

  describe "list_for_user/2" do
    test "returns empty list when the user has no history" do
      assert [] == History.list_for_user(unique_id("nobody"))
    end

    test "returns notifications ordered by created_at desc" do
      user_id = unique_id("u")

      oldest =
        NotificationFixtures.build_notification(%{
          id: unique_id("notif"),
          user_id: user_id,
          created_at: ~U[2026-01-01 10:00:00Z]
        })

      middle =
        NotificationFixtures.build_notification(%{
          id: unique_id("notif"),
          user_id: user_id,
          created_at: ~U[2026-01-02 10:00:00Z]
        })

      newest =
        NotificationFixtures.build_notification(%{
          id: unique_id("notif"),
          user_id: user_id,
          created_at: ~U[2026-01-03 10:00:00Z]
        })

      :ok = History.save(oldest)
      :ok = History.save(middle)
      :ok = History.save(newest)

      ids = History.list_for_user(user_id) |> Enum.map(& &1.id)
      assert ids == [newest.id, middle.id, oldest.id]
    end

    test "honors :limit and :offset for pagination" do
      user_id = unique_id("u")

      notifs =
        for i <- 1..5 do
          NotificationFixtures.build_notification(%{
            id: unique_id("notif"),
            user_id: user_id,
            created_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :hour)
          })
        end

      Enum.each(notifs, &(:ok = History.save(&1)))

      expected_desc = notifs |> Enum.reverse() |> Enum.map(& &1.id)

      first_page = History.list_for_user(user_id, limit: 2) |> Enum.map(& &1.id)
      assert first_page == Enum.take(expected_desc, 2)

      second_page =
        History.list_for_user(user_id, limit: 2, offset: 2) |> Enum.map(& &1.id)

      assert second_page == expected_desc |> Enum.drop(2) |> Enum.take(2)
    end

    test "scopes results to the given user_id" do
      user_a = unique_id("u")
      user_b = unique_id("u")

      for uid <- [user_a, user_b] do
        :ok =
          History.save(
            NotificationFixtures.build_notification(%{id: unique_id("notif"), user_id: uid})
          )
      end

      assert [%Notification{user_id: ^user_a}] = History.list_for_user(user_a)
    end
  end
end
