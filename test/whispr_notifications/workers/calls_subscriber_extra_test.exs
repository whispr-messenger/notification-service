defmodule WhisprNotifications.Workers.CallsSubscriberExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.CallsSubscriber

  test "handle_info :retry_connect stops the process" do
    assert {:stop, :normal, %{pubsub: nil}} =
             CallsSubscriber.handle_info(:retry_connect, %{pubsub: nil})
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
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:calls:initiated", payload: payload}}
    )

    Process.sleep(100)
    assert Process.alive?(pid)
  end
end
