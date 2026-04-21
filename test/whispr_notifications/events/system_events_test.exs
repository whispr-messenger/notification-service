defmodule WhisprNotifications.Events.SystemEventsTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Events.SystemEvents

  test "handle/1 processes a system event" do
    event = %{user_id: "u-sys-1", code: "maintenance", message: "Maintenance in progress"}
    assert :ok = SystemEvents.handle(event)
  end
end
