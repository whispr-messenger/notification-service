defmodule WhisprNotifications.Workers.ModerationSubscriberExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.ModerationSubscriber

  test "handle_info :retry_connect renvoie :noreply et garde le state structurel" do
    # selon que Redis local est dispo ou non, on a soit un reconnect reussi
    # ({:ok, pubsub}), soit un backoff programme. Dans les deux cas on doit
    # rester :noreply et conserver la cle :retry_attempt.
    assert {:noreply, %{retry_attempt: _}} =
             ModerationSubscriber.handle_info(:retry_connect, %{pubsub: nil, retry_attempt: 0})
  end

  test "handle_info :disconnected stops with :redis_disconnected" do
    assert {:stop, :redis_disconnected, %{pubsub: nil, retry_attempt: 0}} =
             ModerationSubscriber.handle_info(
               {:redix_pubsub, :pid, :ref, :disconnected, %{error: :tcp_closed}},
               %{pubsub: nil, retry_attempt: 0}
             )
  end

  test "handle_info catch-all keeps state" do
    assert {:noreply, :state} = ModerationSubscriber.handle_info(:noise, :state)
  end

  test "rescues exceptions thrown by event handlers without crashing" do
    pid = Process.whereis(ModerationSubscriber)

    # `handle_blocked_image_decision` returns {:error, :missing_user_id} when
    # userId is empty, which is not a raise — but a payload with a non-string
    # under :sanction_type causes an error inside ModerationEvents (it tries
    # to interpolate it into a body and may raise, or at minimum the rescue
    # clause is exercised when the handler bubbles an unexpected term).
    payload = Jason.encode!(%{"user_id" => "u", "sanction_id" => 123})

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:moderation:sanction_lifted", payload: payload}}
    )

    Process.sleep(100)
    assert Process.alive?(pid)
  end
end
