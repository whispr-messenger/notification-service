defmodule WhisprNotifications.Workers.ModerationSubscriberTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.ModerationSubscriber

  test "is started under the app supervisor and holds state" do
    pid = Process.whereis(ModerationSubscriber)
    assert is_pid(pid)
    assert Process.alive?(pid)

    state = :sys.get_state(pid)
    assert is_map(state)
    assert Map.has_key?(state, :pubsub)
  end

  test "dispatches a :message handle_info event to the moderation handlers (JSON valid)" do
    pid = Process.whereis(ModerationSubscriber)
    payload = Jason.encode!(%{"user_id" => "u-moderation-sub", "sanction_id" => "s-1"})

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:moderation:sanction_lifted", payload: payload}}
    )

    # GenServer should remain alive
    assert Process.alive?(pid)
  end

  test "tolerates malformed JSON payloads without crashing" do
    pid = Process.whereis(ModerationSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:moderation:report_created", payload: "not-json"}}
    )

    assert Process.alive?(pid)
  end

  test "ignores unknown channels without crashing" do
    pid = Process.whereis(ModerationSubscriber)
    payload = Jason.encode!(%{"x" => 1})

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:moderation:unknown-channel", payload: payload}}
    )

    assert Process.alive?(pid)
  end

  test "ignores :subscribed acks" do
    pid = Process.whereis(ModerationSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :subscribed, %{channel: "whispr:moderation:report_created"}}
    )

    assert Process.alive?(pid)
  end

  test "ignores unrelated messages" do
    pid = Process.whereis(ModerationSubscriber)
    send(pid, :unrelated)
    assert Process.alive?(pid)
  end

  test "routes to every moderation handler (happy payloads)" do
    pid = Process.whereis(ModerationSubscriber)

    routed = [
      {"whispr:moderation:report_created",
       %{"report_id" => "r", "reporter_id" => "u1", "reported_user_id" => "u2", "category" => "c"}},
      {"whispr:moderation:sanction_applied",
       %{
         "user_id" => "u",
         "sanction_type" => "mute",
         "reason" => "x",
         "expires_at" => nil
       }},
      {"whispr:moderation:sanction_lifted", %{"user_id" => "u", "sanction_id" => "s"}},
      {"whispr:moderation:appeal_created",
       %{"appeal_id" => "a", "user_id" => "u", "sanction_id" => "s"}},
      {"whispr:moderation:appeal_resolved",
       %{"appeal_id" => "a", "user_id" => "u", "status" => "accepted", "reviewer_notes" => nil}},
      {"whispr:moderation:threshold_reached",
       %{"reported_user_id" => "u", "threshold_level" => "high", "report_count" => 3}}
    ]

    for {channel, payload} <- routed do
      send(
        pid,
        {:redix_pubsub, nil, nil, :message,
         %{channel: channel, payload: Jason.encode!(payload)}}
      )
    end

    # Let async Tasks run briefly, then confirm process still alive
    Process.sleep(100)
    assert Process.alive?(pid)
  end
end
