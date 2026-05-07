defmodule WhisprNotifications.Delivery.ApnsClientTest do
  @moduledoc """
  Unit tests for `ApnsClient`.

  HTTP/2 + JWT ES256 plumbing is delegated to Pigeon. What we still own:

    * building a valid `%Pigeon.APNS.Notification{}` from the platform
      payload produced by `Formatter.to_platform_payload/3`,
    * mapping every possible `:response` atom back to the
      `ApnsClient.send/2` contract
      (`:ok | {:error, :token_invalid | :transient}`),
    * the short-circuit paths (empty token, APNS disabled, dispatcher not
      running) that must never reach Pigeon.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Pigeon.APNS.Notification, as: APNSNotification
  alias WhisprNotifications.Delivery.ApnsClient
  alias WhisprNotifications.Test.NotificationFixtures

  describe "build_notification/2" do
    test "uses the device token and the device's app as the APNS topic" do
      device = %{token: "ios-token", platform: :ios, app: "com.whispr.app"}

      payload = %{
        "aps" => %{"alert" => %{"title" => "Hi", "body" => "world"}, "sound" => "default"},
        "meta" => %{"notification_id" => "n1"}
      }

      notif = ApnsClient.build_notification(device, payload)

      assert %APNSNotification{
               device_token: "ios-token",
               topic: "com.whispr.app",
               push_type: "alert"
             } = notif

      assert notif.payload == payload
    end

    test "falls back to the configured :default_topic when the device has no app" do
      previous = Application.get_env(:whispr_notification, :apns)

      Application.put_env(:whispr_notification, :apns,
        enabled: false,
        default_topic: "com.whispr.fallback"
      )

      try do
        device = %{token: "t", platform: :ios, app: nil}
        notif = ApnsClient.build_notification(device, %{"aps" => %{}})
        assert notif.topic == "com.whispr.fallback"
      after
        restore(:apns, previous)
      end
    end

    test "wraps a flat {title, body, data} payload into a proper aps envelope" do
      device = NotificationFixtures.build_ios_device()
      notif = ApnsClient.build_notification(device, %{title: "Hi", body: "world"})

      assert get_in(notif.payload, ["aps", "alert", "title"]) == "Hi"
      assert get_in(notif.payload, ["aps", "alert", "body"]) == "world"
      assert get_in(notif.payload, ["aps", "sound"]) == "default"
    end

    test "stringifies the :data sub-map under the meta key when present" do
      device = NotificationFixtures.build_ios_device()

      notif =
        ApnsClient.build_notification(device, %{
          title: "Hi",
          body: "world",
          data: %{:conversation_id => "c-42", :unread => 3}
        })

      meta = get_in(notif.payload, ["meta"])
      assert is_map(meta)
      assert meta["conversation_id"] == "c-42"
      assert meta["unread"] == "3"
    end

    test "passes an arbitrary map payload through unchanged (catch-all clause)" do
      device = NotificationFixtures.build_ios_device()
      payload = %{"foo" => "bar", "without_aps" => true}
      notif = ApnsClient.build_notification(device, payload)
      assert notif.payload == payload
    end
  end

  describe "response_to_result/1" do
    test ":success maps to :ok" do
      assert :ok = ApnsClient.response_to_result(%APNSNotification{response: :success})
    end

    for response <- [
          :bad_device_token,
          :unregistered,
          :device_token_not_for_topic,
          :missing_device_token,
          :expired_token,
          :bad_topic,
          :topic_disallowed,
          :invalid_push_type
        ] do
      test "#{inspect(response)} maps to {:error, :token_invalid}" do
        response = unquote(response)
        notif = %APNSNotification{response: response}
        assert {:error, :token_invalid} = ApnsClient.response_to_result(notif)
      end
    end

    for response <- [
          :internal_server_error,
          :service_unavailable,
          :too_many_requests,
          :too_many_provider_token_updates,
          :expired_provider_token,
          :invalid_provider_token,
          :missing_provider_token,
          :idle_timeout,
          :shutdown,
          :unknown_error,
          :timeout
        ] do
      test "#{inspect(response)} maps to {:error, :transient}" do
        response = unquote(response)
        notif = %APNSNotification{response: response}
        assert {:error, :transient} = ApnsClient.response_to_result(notif)
      end
    end

    test "any unknown response atom degrades to :transient (never drops a token)" do
      notif = %APNSNotification{response: :some_future_atom_from_pigeon}
      assert {:error, :transient} = ApnsClient.response_to_result(notif)
    end
  end

  describe "send/2 — short-circuit paths" do
    setup do
      previous = Application.get_env(:whispr_notification, :apns)

      on_exit(fn -> restore(:apns, previous) end)

      :ok
    end

    test "returns {:error, :not_configured} when the APNS config is absent" do
      Application.delete_env(:whispr_notification, :apns)

      device = NotificationFixtures.build_ios_device()
      assert {:error, :not_configured} = ApnsClient.send(device, %{"aps" => %{}})
    end

    test "returns {:error, :not_configured} when :enabled is false" do
      Application.put_env(:whispr_notification, :apns, enabled: false)

      device = NotificationFixtures.build_ios_device()
      assert {:error, :not_configured} = ApnsClient.send(device, %{"aps" => %{}})
    end

    test "returns {:error, :not_configured} when the dispatcher isn't running" do
      Application.put_env(:whispr_notification, :apns, enabled: true)

      device = NotificationFixtures.build_ios_device()
      assert {:error, :not_configured} = ApnsClient.send(device, %{"aps" => %{}})
    end

    test "returns {:error, :token_invalid} for empty token" do
      assert {:error, :token_invalid} =
               ApnsClient.send(%{token: "", platform: :ios, app: "x"}, %{})
    end

    test "returns {:error, :token_invalid} for nil token" do
      assert {:error, :token_invalid} =
               ApnsClient.send(%{token: nil, platform: :ios, app: "x"}, %{})
    end
  end

  describe "send/2 — dispatcher stub" do
    setup do
      previous_apns = Application.get_env(:whispr_notification, :apns)
      previous_disp = Application.get_env(:whispr_notification, :apns_dispatcher)

      Application.put_env(:whispr_notification, :apns, enabled: true)

      on_exit(fn ->
        restore(:apns, previous_apns)
        restore(:apns_dispatcher, previous_disp)
      end)

      :ok
    end

    test "end-to-end :ok path via a stub dispatcher" do
      defmodule StubApnsDispatcherOK do
        @moduledoc false
        def push(%APNSNotification{} = notif), do: %{notif | response: :success}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubApnsDispatcherOK)
      Application.put_env(:whispr_notification, :apns_dispatcher, StubApnsDispatcherOK)

      device = NotificationFixtures.build_ios_device()

      log =
        capture_log(fn ->
          assert :ok = ApnsClient.send(device, %{"aps" => %{}})
        end)

      assert log =~ "APNS push succeeded"
      Agent.stop(pid)
    end

    test "end-to-end :token_invalid via a stub dispatcher" do
      defmodule StubApnsDispatcherUnreg do
        @moduledoc false
        def push(%APNSNotification{} = notif), do: %{notif | response: :unregistered}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubApnsDispatcherUnreg)
      Application.put_env(:whispr_notification, :apns_dispatcher, StubApnsDispatcherUnreg)

      device = NotificationFixtures.build_ios_device(%{token: "dead-token"})

      log =
        capture_log(fn ->
          assert {:error, :token_invalid} = ApnsClient.send(device, %{"aps" => %{}})
        end)

      assert log =~ "APNS push failed"
      Agent.stop(pid)
    end

    test "end-to-end :transient via a stub dispatcher" do
      defmodule StubApnsDispatcher5xx do
        @moduledoc false
        def push(%APNSNotification{} = notif), do: %{notif | response: :service_unavailable}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubApnsDispatcher5xx)
      Application.put_env(:whispr_notification, :apns_dispatcher, StubApnsDispatcher5xx)

      device = NotificationFixtures.build_ios_device()
      assert {:error, :transient} = ApnsClient.send(device, %{"aps" => %{}})
      Agent.stop(pid)
    end

    test "dispatcher crash is caught and returned as :transient" do
      defmodule StubApnsDispatcherCrash do
        @moduledoc false
        def push(_notif), do: raise("boom")
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubApnsDispatcherCrash)
      Application.put_env(:whispr_notification, :apns_dispatcher, StubApnsDispatcherCrash)

      device = NotificationFixtures.build_ios_device()
      assert {:error, :transient} = ApnsClient.send(device, %{"aps" => %{}})
      Agent.stop(pid)
    end

    test "dispatcher exit is caught and returned as :not_configured" do
      defmodule StubApnsDispatcherExit do
        @moduledoc false
        def push(_notif), do: exit(:dispatcher_dead)
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubApnsDispatcherExit)
      Application.put_env(:whispr_notification, :apns_dispatcher, StubApnsDispatcherExit)

      device = NotificationFixtures.build_ios_device()
      assert {:error, :not_configured} = ApnsClient.send(device, %{"aps" => %{}})
      Agent.stop(pid)
    end

    test "masks the device token in success logs" do
      defmodule StubApnsDispatcherMask do
        @moduledoc false
        def push(%APNSNotification{} = notif), do: %{notif | response: :success}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubApnsDispatcherMask)
      Application.put_env(:whispr_notification, :apns_dispatcher, StubApnsDispatcherMask)

      device = %{token: "abcdef123456789", platform: :ios, app: "com.whispr.app"}

      log =
        capture_log(fn ->
          ApnsClient.send(device, %{"aps" => %{}})
        end)

      assert log =~ "***"
      assert log =~ "56789"
      refute log =~ "abcdef123456789"
      Agent.stop(pid)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, value), do: Application.put_env(:whispr_notification, key, value)
end
