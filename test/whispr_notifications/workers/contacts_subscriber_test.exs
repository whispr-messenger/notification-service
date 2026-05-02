defmodule WhisprNotifications.Workers.ContactsSubscriberTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.ContactsSubscriber

  describe "process_message/2" do
    test "decodes and dispatches a request_received payload" do
      payload =
        Jason.encode!(%{
          "user_id" => "11111111-1111-1111-8111-000000000010",
          "requester_id" => "22222222-2222-2222-8222-000000000010",
          "requester_display_name" => "Alice",
          "request_id" => "33333333-3333-3333-8333-000000000010"
        })

      assert :ok =
               ContactsSubscriber.process_message(
                 "whispr:contacts:request_received",
                 payload
               )
    end

    test "decodes and dispatches a request_accepted payload" do
      payload =
        Jason.encode!(%{
          "user_id" => "11111111-1111-1111-8111-000000000011",
          "accepter_id" => "22222222-2222-2222-8222-000000000011",
          "accepter_display_name" => "Bob",
          "request_id" => "33333333-3333-3333-8333-000000000011"
        })

      assert :ok =
               ContactsSubscriber.process_message(
                 "whispr:contacts:request_accepted",
                 payload
               )
    end

    test "swallows invalid JSON" do
      assert :ok =
               ContactsSubscriber.process_message(
                 "whispr:contacts:request_received",
                 "not-json"
               )
    end

    test "swallows unknown channels" do
      assert :ok =
               ContactsSubscriber.process_message(
                 "whispr:contacts:unknown",
                 Jason.encode!(%{})
               )
    end
  end
end
