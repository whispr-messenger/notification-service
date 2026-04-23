defmodule WhisprNotifications.Security.LoggingTest do
  @moduledoc """
  Guard rails against sensitive data leakage via Logger.

  Asserts that APNS device tokens never appear raw in logs, and that moderation
  identifiers (user_id / report_id / appeal_id / reported_user_id) are passed
  through Logger metadata rather than interpolated into the message string.

  Metadata can be scrubbed by log agents (Loki / Datadog) on the pipeline side;
  values hard-coded into the message body cannot.
  """
  use WhisprNotifications.DataCase, async: false

  import ExUnit.CaptureLog

  alias WhisprNotifications.Delivery.ApnsClient
  alias WhisprNotifications.Events.ModerationEvents

  @sentinel_user "sentinel-user-zzzz"
  @sentinel_report "sentinel-report-zzzz"
  @sentinel_appeal "sentinel-appeal-zzzz"

  setup do
    original = Application.get_env(:whispr_notification, :apns_push_fun)

    on_exit(fn ->
      if original do
        Application.put_env(:whispr_notification, :apns_push_fun, original)
      else
        Application.delete_env(:whispr_notification, :apns_push_fun)
      end
    end)

    :ok
  end

  # The console formatter puts metadata before the level tag and the message
  # after it. Splitting on [level] isolates the message body so we can assert
  # that a sensitive value never appears there.
  defp message_body(log) do
    log
    |> String.split(~r/\[(info|error|warning|debug)\]\s*/, parts: 2)
    |> List.last()
  end

  describe "APNS device token" do
    test "raw token is never written to success logs" do
      raw_token = "fake-ios-token-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      device = %{token: raw_token, platform: :ios, app: "com.whispr.app"}
      Application.put_env(:whispr_notification, :apns_push_fun, fn _, _ -> :ok end)

      log = capture_log([level: :info], fn -> ApnsClient.send(device, %{}) end)

      refute log =~ raw_token
      assert log =~ "***"
    end

    test "raw token is never written to error logs" do
      raw_token = "fake-ios-token-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      device = %{token: raw_token, platform: :ios, app: "com.whispr.app"}

      Application.put_env(:whispr_notification, :apns_push_fun, fn _, _ ->
        {:error, :invalid_device_token}
      end)

      log = capture_log([level: :info], fn -> ApnsClient.send(device, %{}) end)

      refute log =~ raw_token
    end
  end

  describe "moderation events — identifiers must go through metadata" do
    test "report_id is not interpolated in handle_report_created" do
      payload = %{
        "report_id" => @sentinel_report,
        "reporter_id" => "r1",
        "reported_user_id" => "u1",
        "category" => "spam"
      }

      log = capture_log([level: :info], fn -> ModerationEvents.handle_report_created(payload) end)

      refute message_body(log) =~ @sentinel_report
    end

    test "user_id is not interpolated in handle_sanction_applied" do
      payload = %{
        "user_id" => @sentinel_user,
        "sanction_type" => "mute",
        "reason" => "test",
        "expires_at" => nil
      }

      log =
        capture_log([level: :info], fn -> ModerationEvents.handle_sanction_applied(payload) end)

      refute message_body(log) =~ @sentinel_user
    end

    test "user_id is not interpolated in handle_sanction_lifted" do
      payload = %{"user_id" => @sentinel_user, "sanction_id" => "s1"}

      log =
        capture_log([level: :info], fn -> ModerationEvents.handle_sanction_lifted(payload) end)

      refute message_body(log) =~ @sentinel_user
    end

    test "appeal_id and user_id are not interpolated in handle_appeal_created" do
      payload = %{
        "appeal_id" => @sentinel_appeal,
        "user_id" => @sentinel_user,
        "sanction_id" => "s1"
      }

      log = capture_log([level: :info], fn -> ModerationEvents.handle_appeal_created(payload) end)

      body = message_body(log)
      refute body =~ @sentinel_appeal
      refute body =~ @sentinel_user
    end

    test "appeal_id and user_id are not interpolated in handle_appeal_resolved" do
      payload = %{
        "appeal_id" => @sentinel_appeal,
        "user_id" => @sentinel_user,
        "status" => "accepted",
        "reviewer_notes" => nil
      }

      log =
        capture_log([level: :info], fn -> ModerationEvents.handle_appeal_resolved(payload) end)

      body = message_body(log)
      refute body =~ @sentinel_appeal
      refute body =~ @sentinel_user
    end

    test "reported_user_id is not interpolated in handle_threshold_warning" do
      payload = %{
        "reported_user_id" => @sentinel_user,
        "threshold_level" => "high",
        "report_count" => 5
      }

      log =
        capture_log([level: :info], fn -> ModerationEvents.handle_threshold_warning(payload) end)

      refute message_body(log) =~ @sentinel_user
    end

    test "appeal_id is not interpolated in handle_blocked_image_decision warning path" do
      payload = %{"appealId" => @sentinel_appeal, "userId" => nil}

      log =
        capture_log([level: :info], fn ->
          ModerationEvents.handle_blocked_image_decision(payload, "approved")
        end)

      refute message_body(log) =~ @sentinel_appeal
    end

    test "appeal_id and user_id are not interpolated in handle_blocked_image_decision success path" do
      payload = %{
        "appealId" => @sentinel_appeal,
        "userId" => @sentinel_user,
        "conversationId" => "c1",
        "messageTempId" => "t1",
        "reviewerNotes" => nil
      }

      log =
        capture_log([level: :info], fn ->
          ModerationEvents.handle_blocked_image_decision(payload, "approved")
        end)

      body = message_body(log)
      refute body =~ @sentinel_appeal
      refute body =~ @sentinel_user
    end
  end
end
