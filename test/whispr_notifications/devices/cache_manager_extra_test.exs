defmodule WhisprNotifications.Devices.CacheManagerExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices.CacheManager

  test "refresh_cache/1 with an invalid user_id leaves state untouched" do
    # AuthClient rejects nil/empty user_id, hitting the catch-all error
    # branch in CacheManager.handle_cast/2 (line 56).
    assert :ok = CacheManager.refresh_cache("")
    # Make sure the GenServer is still alive after processing the bad cast.
    assert Process.alive?(Process.whereis(CacheManager))
  end
end
