defmodule WhisprNotifications.Events.GroupEventsTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Events.GroupEvents

  test "handle/1 processes :added events" do
    event = %{user_id: "u-g-1", group_id: "g-1", actor_id: "a-1", action: :added}
    assert :ok = GroupEvents.handle(event)
  end

  test "handle/1 processes :removed events" do
    event = %{user_id: "u-g-2", group_id: "g-1", actor_id: "a-1", action: :removed}
    assert :ok = GroupEvents.handle(event)
  end

  test "handle/1 processes :role_changed events" do
    event = %{user_id: "u-g-3", group_id: "g-1", actor_id: "a-1", action: :role_changed}
    assert :ok = GroupEvents.handle(event)
  end
end
