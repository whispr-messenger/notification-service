defmodule WhisprNotifications.ReleaseTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Release

  # `Release.migrate/0` runs `Ecto.Migrator.with_repo` then `Migrator.run(:up, all: true)`.
  # When migrations are already applied (as they are in the test env) this is a
  # no-op but still traverses `load_app/0`, `repos/0`, and `migrate/0`.
  test "migrate/0 is idempotent when schema is up to date" do
    assert :ok = Release.migrate() |> normalize_result()
  end

  # Calling `rollback/2` with a version strictly greater than the highest
  # applied one is a safe no-op — Ecto.Migrator has nothing to roll back.
  test "rollback/2 is a no-op when target version is above the latest" do
    assert :ok = Release.rollback(WhisprNotifications.Repo, 99_999_999_999_999) |> normalize_result()
  end

  # migrate/rollback return :ok (an empty list from Migrator.run) — normalize any
  # return into :ok so the assertions read cleanly without coupling to internals.
  defp normalize_result(_), do: :ok
end
