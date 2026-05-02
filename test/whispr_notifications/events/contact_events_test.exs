defmodule WhisprNotifications.Events.ContactEventsTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Events.ContactEvents

  describe "handle_request_received/1" do
    test "returns :ok for a valid event" do
      event = %{
        user_id: "11111111-1111-1111-8111-000000000001",
        requester_id: "22222222-2222-2222-8222-000000000001",
        requester_display_name: "Alice",
        request_id: "33333333-3333-3333-8333-000000000001"
      }

      assert :ok = ContactEvents.handle_request_received(event)
    end

    test "returns :ok and skips delivery when user_id is missing" do
      assert :ok = ContactEvents.handle_request_received(%{requester_id: "x"})
    end

    test "returns :ok and skips delivery when user_id is empty" do
      assert :ok =
               ContactEvents.handle_request_received(%{
                 user_id: "",
                 requester_id: "22222222-2222-2222-8222-000000000001"
               })
    end
  end

  describe "handle_request_accepted/1" do
    test "returns :ok for a valid event" do
      event = %{
        user_id: "11111111-1111-1111-8111-000000000002",
        accepter_id: "22222222-2222-2222-8222-000000000002",
        accepter_display_name: "Bob",
        request_id: "33333333-3333-3333-8333-000000000002"
      }

      assert :ok = ContactEvents.handle_request_accepted(event)
    end

    test "returns :ok and skips delivery when accepter_id is missing" do
      assert :ok =
               ContactEvents.handle_request_accepted(%{
                 user_id: "11111111-1111-1111-8111-000000000003"
               })
    end
  end
end
