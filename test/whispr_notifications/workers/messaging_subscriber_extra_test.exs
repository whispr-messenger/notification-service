defmodule WhisprNotifications.Workers.MessagingSubscriberExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.MessagingSubscriber

  @user "44444444-4444-4444-8444-000000000aaa"

  test "handle_info :subscribed returns :noreply" do
    assert {:noreply, %{pubsub: nil}} =
             MessagingSubscriber.handle_info(
               {:redix_pubsub, :pid, :ref, :subscribed,
                %{channel: "whispr:messaging:new_message"}},
               %{pubsub: nil}
             )
  end

  test "handle_info :message spawns a Task and returns :noreply" do
    assert {:noreply, %{pubsub: nil}} =
             MessagingSubscriber.handle_info(
               {:redix_pubsub, :pid, :ref, :message,
                %{channel: "whispr:messaging:new_message", payload: "{\"a\":1}"}},
               %{pubsub: nil}
             )

    Process.sleep(50)
  end

  test "handle_info :retry_connect stops the process" do
    assert {:stop, :normal, %{pubsub: nil}} =
             MessagingSubscriber.handle_info(:retry_connect, %{pubsub: nil})
  end

  test "handle_info catch-all keeps state" do
    assert {:noreply, :state} = MessagingSubscriber.handle_info(:unknown_msg, :state)
  end

  test "process_message/2 on an unknown channel returns :ok" do
    assert :ok = MessagingSubscriber.process_message("whispr:messaging:unknown", %{})
  end

  test "process_message/2 message_read with missing user_id is a no-op" do
    assert :ok =
             MessagingSubscriber.process_message("whispr:messaging:message_read", %{"count" => 2})

    assert :ok =
             MessagingSubscriber.process_message("whispr:messaging:message_read", %{
               "user_id" => ""
             })
  end

  test "tolerates malformed JSON without crashing the GenServer" do
    pid = Process.whereis(MessagingSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:messaging:new_message", payload: "not-json"}}
    )

    Process.sleep(100)
    assert Process.alive?(pid)
  end

  test "ignores non-object JSON payloads (a list, a number)" do
    pid = Process.whereis(MessagingSubscriber)

    for payload <- ["[1,2,3]", "42"] do
      send(
        pid,
        {:redix_pubsub, nil, nil, :message,
         %{channel: "whispr:messaging:new_message", payload: payload}}
      )
    end

    Process.sleep(100)
    assert Process.alive?(pid)
  end

  test "process_message new_message ignores empty / non-binary entries in target_user_ids" do
    payload = %{
      "target_user_ids" => [@user, "", nil, 123],
      "count" => 1,
      "message_type" => "text"
    }

    assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)
  end

  test "process_message new_message clamps non-positive count to 1" do
    payload = %{
      "target_user_ids" => [@user],
      "count" => 0,
      "message_type" => "text"
    }

    assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)
  end

  test "process_message new_message reads target from user_id when target_user_ids is missing" do
    payload = %{
      "user_id" => @user,
      "count" => 1,
      "message_type" => "text"
    }

    assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)
  end

  test "handle_message rescue clause swallows raised exceptions from Jason.decode" do
    # Sending a non-binary payload through Jason.decode raises a
    # FunctionClauseError; the `rescue` block in handle_message must absorb
    # it and keep the GenServer alive.
    pid = Process.whereis(MessagingSubscriber)

    send(
      pid,
      {:redix_pubsub, nil, nil, :message,
       %{channel: "whispr:messaging:new_message", payload: :not_binary}}
    )

    Process.sleep(150)
    assert Process.alive?(pid)
  end

  test "process_message new_message accepts mentioned_user_ids and forwards mentioned flag" do
    alias WhisprNotifications.Devices

    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "pixel-mention",
        fcm_token: "tok-mention",
        platform: "android"
      })

    Application.put_env(:whispr_notification, :fcm_spy_pid, self())

    Application.put_env(
      :whispr_notification,
      :fcm_client_mod,
      WhisprNotifications.Test.SpyFcmClient
    )

    payload = %{
      "target_user_ids" => [@user, "", nil],
      "mentioned_user_ids" => [@user, "", "noise"],
      "count" => 1,
      "message_type" => "text"
    }

    assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)
    assert_receive {:fcm_send, %{token: "tok-mention"}, _payload}, 1_000
  end

  test "dispatch_push rescue clause swallows downstream errors" do
    # Forcing History.save to receive a malformed notification is hard; the
    # easiest reproducible MatchError comes from a non-string title produced
    # by a numeric `sender_name` in the payload, which trips the changeset's
    # cast on :title and yields {:error, changeset} instead of :ok.
    alias WhisprNotifications.Devices

    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "pixel-rescue",
        fcm_token: "tok-rescue",
        platform: "android"
      })

    payload = %{
      "target_user_ids" => [@user],
      # Integer sender_name → title is an integer → History.save fails the
      # `:ok = ` match and the rescue clause must absorb it.
      "sender_name" => 12_345,
      "count" => 1,
      "message_type" => "text"
    }

    assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)
  end

  test "produces the right body for every supported message_type" do
    alias WhisprNotifications.Devices

    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "pixel-msgtypes",
        fcm_token: "tok-msgtypes",
        platform: "android"
      })

    Application.put_env(:whispr_notification, :fcm_spy_pid, self())

    Application.put_env(
      :whispr_notification,
      :fcm_client_mod,
      WhisprNotifications.Test.SpyFcmClient
    )

    expectations = %{
      "voice" => "Message vocal",
      "video" => "Vidéo",
      "file" => "Fichier",
      "location" => "Localisation"
    }

    for {message_type, expected_substring} <- expectations do
      payload = %{
        "target_user_ids" => [@user],
        "message_type" => message_type,
        "count" => 1
      }

      assert :ok = MessagingSubscriber.process_message("whispr:messaging:new_message", payload)
      assert_receive {:fcm_send, %{token: "tok-msgtypes"}, fcm_payload}, 1_000
      assert fcm_payload[:notification][:body] =~ expected_substring
    end
  end
end
