defmodule WhisprNotifications.Workers.MessagingSubscriberTest do
  # WHISPR-1159 — MessagingSubscriber calls Notifications.create which
  # queries the DB via CacheManager/AuthClient. Shared sandbox so the
  # long-lived GenServer processes see our transaction.
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.{Badges, Devices}
  alias WhisprNotifications.Notifications.History
  alias WhisprNotifications.Workers.MessagingSubscriber

  @user_a "44444444-4444-4444-8444-000000000001"
  @user_b "44444444-4444-4444-8444-000000000002"
  @sender "44444444-4444-4444-8444-000000000009"
  @conv_id "55555555-5555-5555-8555-000000000001"
  @msg_id "66666666-6666-6666-8666-000000000001"

  setup do
    # Stub FCM so we don't actually hit Google.
    previous_fcm = Application.get_env(:whispr_notification, :fcm_client_mod)

    Application.put_env(
      :whispr_notification,
      :fcm_client_mod,
      WhisprNotifications.Test.SpyFcmClient
    )

    Application.put_env(:whispr_notification, :fcm_spy_pid, self())

    on_exit(fn ->
      if previous_fcm do
        Application.put_env(:whispr_notification, :fcm_client_mod, previous_fcm)
      else
        Application.delete_env(:whispr_notification, :fcm_client_mod)
      end

      Application.delete_env(:whispr_notification, :fcm_spy_pid)
      Application.delete_env(:whispr_notification, :fcm_spy_response)
    end)

    :ok
  end

  describe "process_message/2 new_message" do
    test "increments the badge AND dispatches an FCM push for each recipient's devices" do
      {:ok, _} =
        Devices.upsert(%{
          user_id: @user_a,
          device_id: "pixel-a",
          fcm_token: "tok-a-android",
          platform: "android"
        })

      {:ok, _} =
        Devices.upsert(%{
          user_id: @user_b,
          device_id: "pixel-b",
          fcm_token: "tok-b-android",
          platform: "android"
        })

      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "sender_id" => @sender,
        "target_user_ids" => [@user_a, @user_b],
        "count" => 1,
        "message_type" => "text"
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)

      assert Badges.get(@user_a) == 1
      assert Badges.get(@user_b) == 1

      assert_receive {:fcm_send, %{token: "tok-a-android"}, _payload_a}, 1_000
      assert_receive {:fcm_send, %{token: "tok-b-android"}, _payload_b}, 1_000
    end

    test "builds a generic body from message_type and includes the deeplink context" do
      {:ok, _} =
        Devices.upsert(%{
          user_id: @user_a,
          device_id: "pixel-a",
          fcm_token: "tok-a",
          platform: "android"
        })

      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "sender_id" => @sender,
        "target_user_ids" => [@user_a],
        "message_type" => "photo"
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)

      assert_receive {:fcm_send, %{token: "tok-a"}, fcm_payload}, 1_000

      # Formatter.to_platform_payload wraps title/body under :notification for FCM.
      assert fcm_payload[:notification][:title] == "Nouveau message"
      assert fcm_payload[:notification][:body] =~ "Photo"
      # deeplink context propagated
      assert fcm_payload[:data]["conversation_id"] == @conv_id
      assert fcm_payload[:data]["message_id"] == @msg_id
    end

    test "still bumps the badge when the recipient has no registered device" do
      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "sender_id" => @sender,
        "target_user_ids" => [@user_a],
        "message_type" => "text"
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)

      assert Badges.get(@user_a) == 1
      refute_receive {:fcm_send, _, _}, 200
    end

    test "persists a notification_history row per recipient" do
      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "sender_id" => @sender,
        "target_user_ids" => [@user_a, @user_b],
        "message_type" => "text"
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)

      assert length(History.list_for_user(@user_a)) == 1
      assert length(History.list_for_user(@user_b)) == 1
    end

    test "does nothing when target_user_ids is missing" do
      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "sender_id" => @sender,
        "count" => 1
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)

      refute_receive {:fcm_send, _, _}, 200
    end
  end

  describe "process_message/2 message_read" do
    test "decrements the badge for the reader" do
      Badges.incr(@user_a, 3)

      payload = %{
        "conversation_id" => @conv_id,
        "user_id" => @user_a,
        "message_id" => @msg_id,
        "count" => 2
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:message_read", payload)

      assert Badges.get(@user_a) == 1
    end
  end

  describe "process_message/2 message_deleted" do
    test "broadcasts message_deleted WS event to every recipient" do
      WhisprNotificationsWeb.Endpoint.subscribe("user:#{@user_a}")
      WhisprNotificationsWeb.Endpoint.subscribe("user:#{@user_b}")

      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "target_user_ids" => [@user_a, @user_b]
      }

      assert :ok =
               MessagingSubscriber.process_message(
                 "whispr:messaging:message_deleted",
                 payload
               )

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "message_deleted",
                       payload: %{"message_id" => @msg_id, "conversation_id" => @conv_id}
                     },
                     500

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "message_deleted",
                       payload: %{"message_id" => @msg_id, "conversation_id" => @conv_id}
                     },
                     500
    end

    test "broadcasts to a single recipient via user_id when target_user_ids absent" do
      WhisprNotificationsWeb.Endpoint.subscribe("user:#{@user_a}")

      payload = %{
        "conversation_id" => @conv_id,
        "message_id" => @msg_id,
        "user_id" => @user_a
      }

      assert :ok =
               MessagingSubscriber.process_message(
                 "whispr:messaging:message_deleted",
                 payload
               )

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: "user:#{@user_a}",
                       event: "message_deleted",
                       payload: %{"message_id" => @msg_id, "conversation_id" => @conv_id}
                     },
                     500
    end

    test "is a no-op when recipient list is empty" do
      assert :ok =
               MessagingSubscriber.process_message("whispr:messaging:message_deleted", %{
                 "conversation_id" => @conv_id,
                 "message_id" => @msg_id
               })
    end
  end
end
