defmodule WhisprNotifications.Workers.CallsSubscriberExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.CallsSubscriber

  test "handle_message rescue clause swallows raised exceptions from Jason.decode" do
    pid = Process.whereis(CallsSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:calls:initiated", payload: :not_binary}}
    )

    Process.sleep(150)
    assert Process.alive?(pid)
  end

  test "handle_info :retry_connect renvoie :noreply et garde le state structurel" do
    # selon que Redis local est dispo ou non, on a soit un reconnect reussi
    # ({:ok, pubsub}), soit un backoff programme. Dans les deux cas on doit
    # rester :noreply et conserver la cle :retry_attempt.
    assert {:noreply, %{retry_attempt: _}} =
             CallsSubscriber.handle_info(:retry_connect, %{pubsub: nil, retry_attempt: 1})
  end

  test "handle_info :disconnected stops with :redis_disconnected" do
    assert {:stop, :redis_disconnected, %{pubsub: nil, retry_attempt: 0}} =
             CallsSubscriber.handle_info(
               {:redix_pubsub, :pid, :ref, :disconnected, %{error: :tcp_closed}},
               %{pubsub: nil, retry_attempt: 0}
             )
  end

  test "handle_info catch-all keeps state" do
    assert {:noreply, :state} = CallsSubscriber.handle_info(:bogus, :state)
  end

  test "ignores non-object JSON payloads (an array, a number)" do
    pid = Process.whereis(CallsSubscriber)

    for payload <- ["[1,2]", "12"] do
      send(
        pid,
        {:redix_pubsub, nil, nil, :message,
         %{channel: "whispr:calls:initiated", payload: payload}}
      )
    end

    Process.sleep(100)
    assert Process.alive?(pid)
  end

  test "rescues exceptions thrown by handlers without crashing" do
    # An :initiated payload missing both initiator_id and participants will
    # bubble up through CallsEvents and may raise when the handler tries to
    # build a notification. Make sure the GenServer absorbs it.
    pid = Process.whereis(CallsSubscriber)

    payload = Jason.encode!(%{"call_id" => nil, "type" => "audio"})

    send(
      pid,
      {:redix_pubsub, nil, nil, :message, %{channel: "whispr:calls:initiated", payload: payload}}
    )

    Process.sleep(100)
    assert Process.alive?(pid)
  end
end
