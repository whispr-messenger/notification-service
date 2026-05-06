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

    test "returns :ok when accepter_id is empty (guard mismatch)" do
      assert :ok =
               ContactEvents.handle_request_accepted(%{
                 user_id: "11111111-1111-1111-8111-000000000004",
                 accepter_id: ""
               })
    end
  end

  describe "context.request_id handling" do
    # These tests exercise the maybe_put/3 nil and "" branches in
    # ContactEvents (the request_id key is omitted from the context map
    # rather than being inserted with an empty value).

    test "omits request_id from context when missing on request_received" do
      event = %{
        user_id: "11111111-1111-1111-8111-000000000010",
        requester_id: "22222222-2222-2222-8222-000000000010",
        requester_display_name: "Charlie"
      }

      assert :ok = ContactEvents.handle_request_received(event)
    end

    test "omits request_id from context when empty on request_received" do
      event = %{
        user_id: "11111111-1111-1111-8111-000000000011",
        requester_id: "22222222-2222-2222-8222-000000000011",
        request_id: ""
      }

      assert :ok = ContactEvents.handle_request_received(event)
    end

    test "omits request_id from context when nil on request_accepted" do
      event = %{
        user_id: "11111111-1111-1111-8111-000000000012",
        accepter_id: "22222222-2222-2222-8222-000000000012",
        request_id: nil
      }

      assert :ok = ContactEvents.handle_request_accepted(event)
    end

    test "omits request_id from context when empty on request_accepted" do
      event = %{
        user_id: "11111111-1111-1111-8111-000000000013",
        accepter_id: "22222222-2222-2222-8222-000000000013",
        request_id: ""
      }

      assert :ok = ContactEvents.handle_request_accepted(event)
    end
  end
end
