defmodule WhisprNotifications.BadgesExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Badges
  alias WhisprNotifications.Badges.BadgeCount

  test "decr/2 returns 0 for a user that has no badge row yet" do
    # No row exists in user_badge_counts → update_all hits no rows → the
    # `_ -> 0` fallback in `Badges.decr/2` returns 0.
    assert Badges.decr("never-touched-#{System.unique_integer([:positive])}") == 0
  end

  test "BadgeCount.changeset/1 (default first arg) validates input" do
    # Calling changeset/1 (one-arity) instead of changeset/2 hits the
    # default-arg branch at the function head.
    cs = BadgeCount.changeset(%{user_id: "u", unread_count: 1, updated_at: DateTime.utc_now()})
    assert cs.valid?
  end

  test "BadgeCount.changeset/2 rejects a negative unread_count" do
    cs =
      BadgeCount.changeset(%BadgeCount{}, %{
        user_id: "u",
        unread_count: -3,
        updated_at: DateTime.utc_now()
      })

    refute cs.valid?
    assert {"must be greater than or equal to %{number}", _} =
             Keyword.fetch!(cs.errors, :unread_count)
  end
end
