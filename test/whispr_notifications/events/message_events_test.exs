defmodule WhisprNotifications.Events.MessageEventsTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Events.MessageEvents

  test "handle_new_message/1 completes without raising for a valid event" do
    event = %{
      user_id: "u-msg-1",
      conversation_id: "conv-msg-1",
      message_id: "msg-1",
      sender_id: "sender-1",
      preview: "hi"
    }

    assert :ok = MessageEvents.handle_new_message(event)
  end
end
