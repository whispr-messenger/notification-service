defmodule WhisprNotifications.Notifications.FormatterTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Notifications.Formatter
  alias WhisprNotifications.Test.NotificationFixtures

  describe "to_platform_payload/2 :ios" do
    test "generates valid APNS structure" do
      notif = NotificationFixtures.build_notification()
      payload = Formatter.to_platform_payload(notif, :ios)

      assert %{"aps" => aps} = payload
      assert %{"alert" => %{"title" => "New message", "body" => "Hello from tests"}} = aps
      assert aps["sound"] == "default"
    end

    test "includes notification_id in meta" do
      notif = NotificationFixtures.build_notification(%{id: "notif-42"})
      payload = Formatter.to_platform_payload(notif, :ios)

      assert payload["meta"]["notification_id"] == "notif-42"
    end

    test "includes stringified type in meta" do
      notif = NotificationFixtures.build_notification(%{type: :message})
      payload = Formatter.to_platform_payload(notif, :ios)

      assert payload["meta"]["type"] == "message"
    end

    test "works for all notification types" do
      for type <- [:message, :group, :system] do
        notif = NotificationFixtures.build_notification(%{type: type})
        payload = Formatter.to_platform_payload(notif, :ios)

        assert payload["meta"]["type"] == Atom.to_string(type)
      end
    end
  end

  describe "to_platform_payload/2 :android" do
    test "generates FCM structure with atom keys" do
      notif = NotificationFixtures.build_notification()
      payload = Formatter.to_platform_payload(notif, :android)

      assert %{notification: %{title: "New message", body: "Hello from tests"}} = payload
      assert is_map(payload.data)
    end
  end

  describe "to_platform_payload/2 :web" do
    test "generates web push structure" do
      notif = NotificationFixtures.build_notification()
      payload = Formatter.to_platform_payload(notif, :web)

      assert payload["title"] == "New message"
      assert payload["body"] == "Hello from tests"
      assert is_map(payload["data"])
    end
  end

  describe "collapse_key dedup (WHISPR-1394)" do
    test "android payload carries collapse_key derived from notification id" do
      notif = NotificationFixtures.build_notification(%{id: "msg-id-42"})
      payload = Formatter.to_platform_payload(notif, :android)

      assert payload.collapse_key == "msg:msg-id-42"
    end

    test "ios payload carries collapse_id derived from notification id" do
      notif = NotificationFixtures.build_notification(%{id: "msg-id-42"})
      payload = Formatter.to_platform_payload(notif, :ios)

      assert payload["collapse_id"] == "msg:msg-id-42"
    end

    test "two payloads for the same notification produce the same collapse key" do
      notif = NotificationFixtures.build_notification(%{id: "stable-id"})

      first = Formatter.to_platform_payload(notif, :android)
      second = Formatter.to_platform_payload(notif, :android)

      assert first.collapse_key == second.collapse_key
    end
  end
end
