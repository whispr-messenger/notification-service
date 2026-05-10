defmodule WhisprNotifications.Workers.InboxSubscriberTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Inbox
  alias WhisprNotifications.Workers.InboxSubscriber
  alias WhisprNotificationsWeb.Endpoint

  describe "process_message/1 - logique metier" do
    test "insere un item en DB et broadcast WS sur user:<user_id>" do
      user_id = "dddddddd-dddd-4ddd-8ddd-#{System.unique_integer([:positive])}"
      topic = "user:#{user_id}"
      Endpoint.subscribe(topic)

      msg = %{
        "user_id" => user_id,
        "event_type" => "mention",
        "payload" => %{"conversation_id" => "conv-test"}
      }

      assert :ok = InboxSubscriber.process_message(msg)

      # verifie que le broadcast WS est arrive
      assert_receive %Phoenix.Socket.Broadcast{
                       topic: ^topic,
                       event: "inbox:new",
                       payload: %{event_type: "mention"}
                     },
                     500

      # verifie que l'item est bien en DB
      items = Inbox.list(user_id)
      assert length(items) == 1
      assert hd(items).event_type == "mention"
    end

    test "ignore un event_type inconnu sans crash" do
      user_id = "dddddddd-dddd-4ddd-8ddd-#{System.unique_integer([:positive])}"
      Endpoint.subscribe("user:#{user_id}")

      msg = %{
        "user_id" => user_id,
        "event_type" => "unknown_event",
        "payload" => %{}
      }

      assert :ok = InboxSubscriber.process_message(msg)

      # pas de broadcast attendu
      refute_receive %Phoenix.Socket.Broadcast{event: "inbox:new"}, 200

      # pas d'item en DB
      assert Inbox.list(user_id) == []
    end

    test "message malformed (champs manquants) ne crash pas" do
      assert :ok = InboxSubscriber.process_message(%{"foo" => "bar"})
      assert :ok = InboxSubscriber.process_message(%{})
    end

    test "accepte tous les event_types valides et broadcast pour chacun" do
      user_id = "eeeeeeee-eeee-4eee-8eee-#{System.unique_integer([:positive])}"
      topic = "user:#{user_id}"
      Endpoint.subscribe(topic)

      for event_type <- ~w(mention reply contact_request missed_call) do
        msg = %{
          "user_id" => user_id,
          "event_type" => event_type,
          "payload" => %{"e" => event_type}
        }

        assert :ok = InboxSubscriber.process_message(msg)

        assert_receive %Phoenix.Socket.Broadcast{
                         topic: ^topic,
                         event: "inbox:new"
                       },
                       500
      end

      assert length(Inbox.list(user_id)) == 4
    end
  end

  describe "handle_info/2" do
    test "est demarre sous le superviseur et est vivant" do
      pid = Process.whereis(InboxSubscriber)
      assert is_pid(pid)
      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert is_map(state)
      assert Map.has_key?(state, :pubsub)
    end

    test ":subscribed retourne :noreply sans changer le state" do
      state = %{pubsub: nil, retry_attempt: 0}

      assert {:noreply, ^state} =
               InboxSubscriber.handle_info(
                 {:redix_pubsub, :pid, :ref, :subscribed,
                  %{channel: "whispr:notifications:inbox"}},
                 state
               )
    end

    test ":message lance une Task et retourne :noreply" do
      state = %{pubsub: nil, retry_attempt: 0}

      assert {:noreply, ^state} =
               InboxSubscriber.handle_info(
                 {:redix_pubsub, :pid, :ref, :message,
                  %{channel: "whispr:notifications:inbox", payload: "{}"}},
                 state
               )

      Process.sleep(50)
    end

    test ":disconnected stoppe avec :redis_disconnected" do
      state = %{pubsub: nil, retry_attempt: 0}

      assert {:stop, :redis_disconnected, ^state} =
               InboxSubscriber.handle_info(
                 {:redix_pubsub, :pid, :ref, :disconnected, %{error: :tcp_closed}},
                 state
               )
    end

    test ":retry_connect reste :noreply" do
      assert {:noreply, %{retry_attempt: _}} =
               InboxSubscriber.handle_info(:retry_connect, %{pubsub: nil, retry_attempt: 1})
    end

    test "catch-all garde le state" do
      assert {:noreply, :state} = InboxSubscriber.handle_info(:noise, :state)
    end

    test "JSON invalide ne crash pas le GenServer" do
      pid = Process.whereis(InboxSubscriber)

      send(
        pid,
        {:redix_pubsub, nil, nil, :message,
         %{channel: "whispr:notifications:inbox", payload: "not-json"}}
      )

      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end
end
