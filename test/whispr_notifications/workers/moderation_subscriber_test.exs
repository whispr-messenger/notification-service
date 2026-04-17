defmodule WhisprNotifications.Workers.ModerationSubscriberTest do
  use ExUnit.Case, async: false

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

  describe "handle_info/2 direct invocation" do
    test "returns {:stop, :normal, state} for :retry_connect" do
      assert {:stop, :normal, %{pubsub: nil}} =
               ModerationSubscriber.handle_info(:retry_connect, %{pubsub: nil})
    end

    test "ignores :subscribed callback payload" do
      assert {:noreply, %{pubsub: :fake}} =
               ModerationSubscriber.handle_info(
                 {:redix_pubsub, :fake, :ref, :subscribed, %{channel: "x"}},
                 %{pubsub: :fake}
               )
    end

    test "ignores unrelated messages" do
      assert {:noreply, %{pubsub: nil}} =
               ModerationSubscriber.handle_info(:anything_else, %{pubsub: nil})
    end
  end

  describe "build_redix_opts/0" do
    setup do
      original = Application.get_env(:whispr_notification, :redis)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:whispr_notification, :redis)
        else
          Application.put_env(:whispr_notification, :redis, original)
        end
      end)

      :ok
    end

    test "returns host/port opts when no sentinels are configured" do
      Application.put_env(:whispr_notification, :redis,
        host: "redis.internal",
        port: 7000,
        database: 3
      )

      opts = ModerationSubscriber.build_redix_opts()

      assert Keyword.get(opts, :host) == "redis.internal"
      assert Keyword.get(opts, :port) == 7000
      assert Keyword.get(opts, :database) == 3
      refute Keyword.has_key?(opts, :sentinel)
    end

    test "returns sentinel opts when :sentinels is a non-empty list" do
      Application.put_env(:whispr_notification, :redis,
        sentinels: ["sentinel-1:26379", "sentinel-2"],
        group: "whispr-master",
        database: 1
      )

      opts = ModerationSubscriber.build_redix_opts()

      assert Keyword.get(opts, :database) == 1
      assert [sentinels: sentinels, group: "whispr-master"] = Keyword.get(opts, :sentinel)
      assert [host: "sentinel-1", port: 26_379] in sentinels
      assert [host: "sentinel-2", port: 26_379] in sentinels
    end

    test "includes :password only when non-empty" do
      placeholder = Enum.join(~w(redis token test), "-")

      Application.put_env(:whispr_notification, :redis,
        host: "redis",
        port: 6379,
        password: placeholder
      )

      assert ModerationSubscriber.build_redix_opts() |> Keyword.get(:password) ==
               placeholder

      Application.put_env(:whispr_notification, :redis,
        host: "redis",
        port: 6379,
        password: ""
      )

      refute ModerationSubscriber.build_redix_opts() |> Keyword.has_key?(:password)

      Application.put_env(:whispr_notification, :redis,
        host: "redis",
        port: 6379,
        password: nil
      )

      refute ModerationSubscriber.build_redix_opts() |> Keyword.has_key?(:password)
    end

    test "uses default sentinel group when not specified" do
      Application.put_env(:whispr_notification, :redis, sentinels: ["a:26379"])

      opts = ModerationSubscriber.build_redix_opts()

      assert opts |> Keyword.get(:sentinel) |> Keyword.get(:group) == "mymaster"
    end
  end

  describe "parse_sentinel/1" do
    test "parses host:port binary" do
      assert ModerationSubscriber.parse_sentinel("redis.svc:26380") ==
               [host: "redis.svc", port: 26_380]
    end

    test "uses port 26379 for host-only binary" do
      assert ModerationSubscriber.parse_sentinel("redis.svc") ==
               [host: "redis.svc", port: 26_379]
    end

    test "passes through keyword list entries" do
      assert ModerationSubscriber.parse_sentinel(host: "x", port: 1234) ==
               [host: "x", port: 1234]
    end
  end

  describe "maybe_add_password/2" do
    test "returns opts unchanged for nil/empty password" do
      assert ModerationSubscriber.maybe_add_password([host: "x"], nil) == [host: "x"]
      assert ModerationSubscriber.maybe_add_password([host: "x"], "") == [host: "x"]
    end

    test "adds :password when set" do
      value = Enum.join(~w(redis token), "-")
      opts = ModerationSubscriber.maybe_add_password([host: "x"], value)
      assert Keyword.get(opts, :host) == "x"
      assert Keyword.get(opts, :password) == value
    end
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
