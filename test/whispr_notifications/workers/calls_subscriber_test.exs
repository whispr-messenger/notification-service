defmodule WhisprNotifications.Workers.CallsSubscriberTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.CallsSubscriber
  alias WhisprNotificationsWeb.Endpoint

  test "is started under the app supervisor and holds state" do
    pid = Process.whereis(CallsSubscriber)
    assert is_pid(pid)
    assert Process.alive?(pid)

    state = :sys.get_state(pid)
    assert is_map(state)
    assert Map.has_key?(state, :pubsub)
  end

  test "process_message/2 on :initiated broadcasts incoming_call WS for each participant" do
    user_a = "user-a-#{System.unique_integer([:positive])}"
    user_b = "user-b-#{System.unique_integer([:positive])}"

    Endpoint.subscribe("user:#{user_a}")
    Endpoint.subscribe("user:#{user_b}")

    payload = %{
      "call_id" => "call-1",
      "initiator_id" => user_a,
      "conversation_id" => "conv-1",
      "participant_ids" => [user_a, user_b],
      "type" => "audio"
    }

    assert :ok = CallsSubscriber.process_message("whispr:calls:initiated", payload)

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: topic_a,
                     event: "incoming_call",
                     payload: %{"call_id" => "call-1"}
                   },
                   500

    assert topic_a in ["user:#{user_a}", "user:#{user_b}"]

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: topic_b,
                     event: "incoming_call",
                     payload: %{"call_id" => "call-1"}
                   },
                   500

    assert topic_b in ["user:#{user_a}", "user:#{user_b}"]
    assert topic_a != topic_b
  end

  test "process_message/2 on :accepted broadcasts call_accepted WS" do
    user_id = "user-accept-#{System.unique_integer([:positive])}"
    Endpoint.subscribe("user:#{user_id}")

    payload = %{"call_id" => "call-2", "user_id" => user_id}

    assert :ok = CallsSubscriber.process_message("whispr:calls:accepted", payload)

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: topic,
                     event: "call_accepted",
                     payload: %{"call_id" => "call-2", "user_id" => ^user_id}
                   },
                   500

    assert topic == "user:#{user_id}"
  end

  test "process_message/2 on :declined broadcasts call_declined WS" do
    user_id = "user-decline-#{System.unique_integer([:positive])}"
    Endpoint.subscribe("user:#{user_id}")

    payload = %{"call_id" => "call-3", "user_id" => user_id}

    assert :ok = CallsSubscriber.process_message("whispr:calls:declined", payload)

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "call_declined",
                     payload: %{"call_id" => "call-3"}
                   },
                   500
  end

  test "process_message/2 on :ended broadcasts call_ended WS to every participant" do
    user_a = "user-end-a-#{System.unique_integer([:positive])}"
    user_b = "user-end-b-#{System.unique_integer([:positive])}"
    Endpoint.subscribe("user:#{user_a}")
    Endpoint.subscribe("user:#{user_b}")

    payload = %{
      "call_id" => "call-4",
      "duration_seconds" => 120,
      "end_reason" => "hangup",
      "participants" => [user_a, user_b]
    }

    assert :ok = CallsSubscriber.process_message("whispr:calls:ended", payload)

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: topic_a,
                     event: "call_ended",
                     payload: %{"call_id" => "call-4", "duration_seconds" => 120}
                   },
                   500

    assert topic_a in ["user:#{user_a}", "user:#{user_b}"]

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: topic_b,
                     event: "call_ended"
                   },
                   500

    assert topic_b in ["user:#{user_a}", "user:#{user_b}"]
    assert topic_a != topic_b
  end

  test "process_message/2 on :missed broadcasts call_missed WS" do
    user_id = "user-missed-#{System.unique_integer([:positive])}"
    Endpoint.subscribe("user:#{user_id}")

    payload = %{"call_id" => "call-5", "user_id" => user_id}

    assert :ok = CallsSubscriber.process_message("whispr:calls:missed", payload)

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "call_missed",
                     payload: %{"call_id" => "call-5"}
                   },
                   500
  end

  test "tolerates malformed JSON without crashing" do
    pid = Process.whereis(CallsSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:calls:initiated", payload: "not-json"}}
    )

    Process.sleep(100)
    assert Process.alive?(pid)
  end

  test "ignores unknown channels without crashing" do
    pid = Process.whereis(CallsSubscriber)
    payload = Jason.encode!(%{"x" => 1})

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:calls:unknown-event", payload: payload}}
    )

    Process.sleep(50)
    assert Process.alive?(pid)
  end

  test "ignores :subscribed acks" do
    pid = Process.whereis(CallsSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :subscribed, %{channel: "whispr:calls:initiated"}}
    )

    assert Process.alive?(pid)
  end

  test "handles :initiated payload missing participant_ids without crashing" do
    pid = Process.whereis(CallsSubscriber)

    payload =
      Jason.encode!(%{
        "call_id" => "call-malformed",
        "initiator_id" => "user-x",
        "type" => "audio"
      })

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:calls:initiated", payload: payload}}
    )

    Process.sleep(100)
    assert Process.alive?(pid)
  end

  test "dispatches a :message handle_info event end-to-end (JSON valid)" do
    pid = Process.whereis(CallsSubscriber)

    payload =
      Jason.encode!(%{
        "call_id" => "call-end2end",
        "user_id" => "user-e2e"
      })

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:calls:accepted", payload: payload}}
    )

    # GenServer should remain alive after async Task completes
    Process.sleep(100)
    assert Process.alive?(pid)
  end
end
