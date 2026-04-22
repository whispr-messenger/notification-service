defmodule WhisprNotifications.Test.NotificationFixtures do
  @moduledoc false

  alias WhisprNotifications.Devices.DeviceCache
  alias WhisprNotifications.Notifications.Notification

  # Must be a valid UUID so it serialises against the `uuid` column type.
  @default_id "11111111-1111-1111-1111-000000000001"
  @default_user_id "user-test-001"

  defp fake_token(prefix) do
    prefix <> "-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  def build_notification(overrides \\ %{}) do
    defaults = %{
      id: @default_id,
      user_id: @default_user_id,
      type: :message,
      title: "New message",
      body: "Hello from tests",
      context: %{"conversation_id" => "conv-1"},
      created_at: ~U[2026-01-01 12:00:00Z]
    }

    Notification.new(Map.merge(defaults, overrides))
  end

  def build_ios_device(overrides \\ %{}) do
    Map.merge(
      %{token: fake_token("test-ios"), platform: :ios, app: "com.whispr.app"},
      overrides
    )
  end

  def build_android_device(overrides \\ %{}) do
    Map.merge(
      %{token: fake_token("test-android"), platform: :android, app: nil},
      overrides
    )
  end

  def build_web_device(overrides \\ %{}) do
    Map.merge(
      %{token: fake_token("test-web"), platform: :web, app: nil},
      overrides
    )
  end

  def build_device_cache(overrides \\ []) do
    user_id = Keyword.get(overrides, :user_id, @default_user_id)
    devices = Keyword.get(overrides, :devices, [build_ios_device()])

    %DeviceCache{user_id: user_id, devices: devices}
  end
end
