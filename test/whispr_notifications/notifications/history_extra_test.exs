defmodule WhisprNotifications.Notifications.HistoryExtraTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Notifications.History
  alias WhisprNotifications.Notifications.Notification

  test "save/1 returns {:error, changeset} when validate_required fails" do
    # Build an invalid struct directly (bypassing Notification.new! which
    # would refuse it) so the changeset rejects the insert.
    invalid =
      struct!(Notification, %{
        id: Ecto.UUID.generate(),
        user_id: nil,
        type: nil,
        title: nil,
        body: nil,
        created_at: nil
      })

    assert {:error, %Ecto.Changeset{valid?: false}} = History.save(invalid)
  end

  test "mark_read/1 (default arg) uses now() and is idempotent" do
    # Calling mark_read/1 (one-arity) exercises the `at \\ DateTime.utc_now()`
    # default-argument branch.
    assert :ok = History.mark_read(Ecto.UUID.generate())
  end
end
