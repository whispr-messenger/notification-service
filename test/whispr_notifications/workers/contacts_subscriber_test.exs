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

  describe "handle_info/2" do
    test ":subscribed retourne :noreply" do
      assert {:noreply, %{pubsub: nil, retry_attempt: 0}} =
               ContactsSubscriber.handle_info(
                 {:redix_pubsub, :pid, :ref, :subscribed,
                  %{channel: "whispr:contacts:request_received"}},
                 %{pubsub: nil, retry_attempt: 0}
               )
    end

    test ":message lance une Task et retourne :noreply" do
      assert {:noreply, %{pubsub: nil, retry_attempt: 0}} =
               ContactsSubscriber.handle_info(
                 {:redix_pubsub, :pid, :ref, :message,
                  %{channel: "whispr:contacts:request_received", payload: "{}"}},
                 %{pubsub: nil, retry_attempt: 0}
               )

      Process.sleep(50)
    end

    test ":disconnected stoppe avec :redis_disconnected pour laisser le Supervisor relancer" do
      assert {:stop, :redis_disconnected, %{pubsub: nil, retry_attempt: 0}} =
               ContactsSubscriber.handle_info(
                 {:redix_pubsub, :pid, :ref, :disconnected, %{error: :tcp_closed}},
                 %{pubsub: nil, retry_attempt: 0}
               )
    end

    test ":retry_connect renvoie :noreply en gardant la cle :retry_attempt" do
      # selon que Redis local est dispo ou non, on a soit un reconnect reussi
      # soit un backoff programme. Dans les deux cas on doit rester :noreply.
      assert {:noreply, %{retry_attempt: _}} =
               ContactsSubscriber.handle_info(:retry_connect, %{pubsub: nil, retry_attempt: 2})
    end

    test "catch-all garde le state" do
      assert {:noreply, :state} = ContactsSubscriber.handle_info(:noise, :state)
    end
  end
end
