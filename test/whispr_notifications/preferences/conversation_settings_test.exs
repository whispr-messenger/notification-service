defmodule WhisprNotifications.Preferences.ConversationSettingsTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Preferences.ConversationSettings

  describe "muted_now?/2" do
    test "returns false when not muted" do
      s = %ConversationSettings{user_id: "u", conversation_id: "c", muted: false}
      refute ConversationSettings.muted_now?(s, ~U[2026-01-01 00:00:00Z])
    end

    test "returns true when muted indefinitely (mute_until nil)" do
      s = %ConversationSettings{user_id: "u", conversation_id: "c", muted: true}
      assert ConversationSettings.muted_now?(s, ~U[2026-01-01 00:00:00Z])
    end

    test "returns true when muted with mute_until in the future" do
      s = %ConversationSettings{
        user_id: "u",
        conversation_id: "c",
        muted: true,
        mute_until: ~U[2026-06-01 00:00:00Z]
      }

      assert ConversationSettings.muted_now?(s, ~U[2026-01-01 00:00:00Z])
    end

    test "returns false when mute_until is in the past" do
      s = %ConversationSettings{
        user_id: "u",
        conversation_id: "c",
        muted: true,
        mute_until: ~U[2025-01-01 00:00:00Z]
      }

      refute ConversationSettings.muted_now?(s, ~U[2026-01-01 00:00:00Z])
    end
  end
end
