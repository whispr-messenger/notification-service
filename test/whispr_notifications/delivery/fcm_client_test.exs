defmodule WhisprNotifications.Delivery.FcmClientTest do
  @moduledoc """
  Unit tests for `FcmClient`.

  Now that the HTTP/OAuth plumbing is delegated to Pigeon, we no longer own
  the network boundary — we trust Pigeon's own test suite for that. What
  stays in our responsibility:

    * building a valid `%Pigeon.FCM.Notification{}` from our internal
      payload shape (what BatchProcessor hands us),
    * mapping every possible `:response` atom back to the
      `FcmClient.send/2` contract (`:ok | {:error, :token_invalid | :transient}`),
    * the short-circuit paths (empty token, FCM disabled, dispatcher not
      running) that must never reach Pigeon.

  End-to-end behaviour through a real or stub dispatcher is covered by
  `batch_processor_test.exs` via `SpyFcmClient`.
  """
  use ExUnit.Case, async: false

  alias Pigeon.FCM.Notification, as: FCMNotification
  alias WhisprNotifications.Delivery.FcmClient

  describe "build_notification/3" do
    test "targets the device token and carries title/body from a flat payload" do
      notif =
        FcmClient.build_notification("android-token", :android, %{title: "Hi", body: "world"})

      assert %FCMNotification{target: {:token, "android-token"}} = notif
      assert notif.notification == %{"title" => "Hi", "body" => "world"}
    end

    test "reads title/body from a nested `:notification` key as well" do
      payload = %{notification: %{title: "From nested", body: "also ok"}}
      notif = FcmClient.build_notification("t", :android, payload)

      assert notif.notification == %{"title" => "From nested", "body" => "also ok"}
    end

    test "forwards `:data` as string-keyed, string-valued map" do
      payload = %{title: "t", body: "b", data: %{"cid" => "conv-1", :source => :app}}
      notif = FcmClient.build_notification("t", :android, payload)

      assert notif.data == %{"cid" => "conv-1", "source" => "app"}
    end

    test "omits data when the payload has no data or empty data" do
      assert FcmClient.build_notification("t", :android, %{title: "t", body: "b"}).data == nil

      assert FcmClient.build_notification("t", :android, %{title: "t", body: "b", data: %{}}).data ==
               nil
    end

    test "sets Android priority HIGH for :android platform" do
      notif = FcmClient.build_notification("t", :android, %{title: "t", body: "b"})
      assert notif.android == %{"priority" => "HIGH"}
    end

    test "carries collapse_key in android map when payload provides it (WHISPR-1394)" do
      payload = %{title: "t", body: "b", collapse_key: "msg:abc-123"}
      notif = FcmClient.build_notification("t", :android, payload)

      assert notif.android == %{"priority" => "HIGH", "collapse_key" => "msg:abc-123"}
    end

    test "omits collapse_key when payload key is absent or empty" do
      # absent : aucun ajout sur l'android map
      notif1 = FcmClient.build_notification("t", :android, %{title: "t", body: "b"})
      refute Map.has_key?(notif1.android, "collapse_key")

      # empty string : on ne pose rien
      notif2 =
        FcmClient.build_notification("t", :android, %{title: "t", body: "b", collapse_key: ""})

      refute Map.has_key?(notif2.android, "collapse_key")
    end

    test "leaves android nil for non-android platforms" do
      assert FcmClient.build_notification("t", :ios, %{title: "t", body: "b"}).android == nil
      assert FcmClient.build_notification("t", :web, %{title: "t", body: "b"}).android == nil
    end
  end

  describe "response_to_result/1" do
    test ":success maps to :ok" do
      assert :ok = FcmClient.response_to_result(%FCMNotification{response: :success})
    end

    for response <- [:unregistered, :invalid_argument, :sender_id_mismatch] do
      test "#{inspect(response)} maps to {:error, :token_invalid}" do
        response = unquote(response)
        notif = %FCMNotification{response: response}
        assert {:error, :token_invalid} = FcmClient.response_to_result(notif)
      end
    end

    for response <- [
          :permission_denied,
          :third_party_auth_error,
          :quota_exceeded,
          :unavailable,
          :internal,
          :unspecified_error,
          :unknown_error
        ] do
      test "#{inspect(response)} maps to {:error, :transient}" do
        response = unquote(response)
        notif = %FCMNotification{response: response}
        assert {:error, :transient} = FcmClient.response_to_result(notif)
      end
    end

    test "any unknown response atom degrades to :transient (never drops a token)" do
      notif = %FCMNotification{response: :some_future_atom_from_pigeon}
      assert {:error, :transient} = FcmClient.response_to_result(notif)
    end
  end

  describe "send/2 — short-circuit paths" do
    setup do
      previous = Application.get_env(:whispr_notification, :fcm)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:whispr_notification, :fcm)
        else
          Application.put_env(:whispr_notification, :fcm, previous)
        end
      end)

      :ok
    end

    test "returns {:error, :not_configured} when the FCM config is absent" do
      Application.delete_env(:whispr_notification, :fcm)

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :not_configured} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "returns {:error, :not_configured} when :enabled is false" do
      Application.put_env(:whispr_notification, :fcm, enabled: false)

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :not_configured} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "returns {:error, :not_configured} when the dispatcher isn't running" do
      # enabled = true but no dispatcher in the supervision tree (test env)
      Application.put_env(:whispr_notification, :fcm,
        project_id: "proj",
        enabled: true,
        credentials: %{}
      )

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :not_configured} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "returns {:error, :token_invalid} for empty token" do
      assert {:error, :token_invalid} =
               FcmClient.send(%{token: "", platform: :android, app: nil}, %{})
    end

    test "returns {:error, :token_invalid} for nil token" do
      assert {:error, :token_invalid} =
               FcmClient.send(%{token: nil, platform: :android, app: nil}, %{})
    end
  end

  describe "send/2 — dispatcher stub" do
    setup do
      previous_fcm = Application.get_env(:whispr_notification, :fcm)
      previous_disp = Application.get_env(:whispr_notification, :fcm_dispatcher)

      Application.put_env(:whispr_notification, :fcm,
        project_id: "proj",
        enabled: true,
        credentials: %{}
      )

      on_exit(fn ->
        restore(:fcm, previous_fcm)
        restore(:fcm_dispatcher, previous_disp)
      end)

      :ok
    end

    defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
    defp restore(key, value), do: Application.put_env(:whispr_notification, key, value)

    test "end-to-end :ok path via a stub dispatcher" do
      defmodule StubDispatcherOK do
        @moduledoc false
        def push(%Pigeon.FCM.Notification{} = notif), do: %{notif | response: :success}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubDispatcherOK)
      Application.put_env(:whispr_notification, :fcm_dispatcher, StubDispatcherOK)

      device = %{token: "tok", platform: :android, app: nil}
      assert :ok = FcmClient.send(device, %{title: "t", body: "b"})
      Agent.stop(pid)
    end

    test "end-to-end :token_invalid via a stub dispatcher" do
      defmodule StubDispatcherUnreg do
        @moduledoc false
        def push(%Pigeon.FCM.Notification{} = notif), do: %{notif | response: :unregistered}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubDispatcherUnreg)
      Application.put_env(:whispr_notification, :fcm_dispatcher, StubDispatcherUnreg)

      device = %{token: "dead", platform: :android, app: nil}
      assert {:error, :token_invalid} = FcmClient.send(device, %{title: "t", body: "b"})
      Agent.stop(pid)
    end

    test "end-to-end :transient via a stub dispatcher" do
      defmodule StubDispatcher5xx do
        @moduledoc false
        def push(%Pigeon.FCM.Notification{} = notif), do: %{notif | response: :unavailable}
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubDispatcher5xx)
      Application.put_env(:whispr_notification, :fcm_dispatcher, StubDispatcher5xx)

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :transient} = FcmClient.send(device, %{title: "t", body: "b"})
      Agent.stop(pid)
    end

    test "dispatcher crash is caught and returned as :transient" do
      defmodule StubDispatcherCrash do
        @moduledoc false
        def push(_notif), do: raise("boom")
      end

      {:ok, pid} = Agent.start_link(fn -> :ok end, name: StubDispatcherCrash)
      Application.put_env(:whispr_notification, :fcm_dispatcher, StubDispatcherCrash)

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :transient} = FcmClient.send(device, %{title: "t", body: "b"})
      Agent.stop(pid)
    end
  end
end
