defmodule WhisprNotifications.Preferences.UserSettingsTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Preferences.UserSettings

  describe "quiet_now?/2 (no quiet hours)" do
    test "returns false when both start/end are nil" do
      settings = %UserSettings{user_id: "u-1"}
      refute UserSettings.quiet_now?(settings, ~U[2026-01-01 12:00:00Z])
    end
  end

  describe "quiet_now?/2 same-day window" do
    setup do
      settings = %UserSettings{
        user_id: "u-1",
        quiet_hours_start: ~T[09:00:00],
        quiet_hours_end: ~T[17:00:00]
      }

      {:ok, settings: settings}
    end

    test "returns true at the beginning of the window", %{settings: s} do
      assert UserSettings.quiet_now?(s, ~U[2026-01-01 09:00:00Z])
    end

    test "returns true in the middle of the window", %{settings: s} do
      assert UserSettings.quiet_now?(s, ~U[2026-01-01 12:30:00Z])
    end

    test "returns true at the end of the window", %{settings: s} do
      assert UserSettings.quiet_now?(s, ~U[2026-01-01 17:00:00Z])
    end

    test "returns false before the window", %{settings: s} do
      refute UserSettings.quiet_now?(s, ~U[2026-01-01 08:59:59Z])
    end

    test "returns false after the window", %{settings: s} do
      refute UserSettings.quiet_now?(s, ~U[2026-01-01 17:00:01Z])
    end
  end

  describe "quiet_now?/2 midnight-crossing window" do
    setup do
      settings = %UserSettings{
        user_id: "u-1",
        quiet_hours_start: ~T[22:00:00],
        quiet_hours_end: ~T[07:00:00]
      }

      {:ok, settings: settings}
    end

    test "returns true late in the evening", %{settings: s} do
      assert UserSettings.quiet_now?(s, ~U[2026-01-01 23:30:00Z])
    end

    test "returns true early in the morning", %{settings: s} do
      assert UserSettings.quiet_now?(s, ~U[2026-01-01 05:00:00Z])
    end

    test "returns false during the day", %{settings: s} do
      refute UserSettings.quiet_now?(s, ~U[2026-01-01 12:00:00Z])
    end
  end

  describe "quiet_now?/2 with timezone" do
    test "shifts the comparison into the given timezone" do
      settings = %UserSettings{
        user_id: "u-1",
        timezone: "Etc/UTC",
        quiet_hours_start: ~T[09:00:00],
        quiet_hours_end: ~T[17:00:00]
      }

      assert UserSettings.quiet_now?(settings, ~U[2026-01-01 12:00:00Z])
      refute UserSettings.quiet_now?(settings, ~U[2026-01-01 18:00:00Z])
    end
  end

  describe "quiet_now?/2 defensive branches" do
    test "returns false when only start is nil" do
      settings = %UserSettings{
        user_id: "u-1",
        quiet_hours_start: nil,
        quiet_hours_end: ~T[07:00:00]
      }

      refute UserSettings.quiet_now?(settings, ~U[2026-01-01 12:00:00Z])
    end

    test "returns false when only end is nil" do
      settings = %UserSettings{
        user_id: "u-1",
        quiet_hours_start: ~T[22:00:00],
        quiet_hours_end: nil
      }

      refute UserSettings.quiet_now?(settings, ~U[2026-01-01 12:00:00Z])
    end
  end
end
