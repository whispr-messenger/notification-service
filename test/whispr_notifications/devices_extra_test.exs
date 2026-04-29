defmodule WhisprNotifications.DevicesExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices

  test "soft_delete/1 returns {:error, :not_found} for an unknown id" do
    assert {:error, :not_found} = Devices.soft_delete(Ecto.UUID.generate())
  end

  test "mark_invalid/1 (default reason) marks an existing token invalid" do
    user_id = "11111111-1111-4111-8111-000000000777"

    {:ok, _} =
      Devices.upsert(%{
        user_id: user_id,
        device_id: "default-reason",
        fcm_token: "tok-default-reason",
        platform: "android"
      })

    # mark_invalid/1 (no second arg) hits the default-arg variant on line 84.
    assert :ok = Devices.mark_invalid("tok-default-reason")
  end

  test "mark_invalid/2 returns {:error, :not_found} when token doesn't exist" do
    assert {:error, :not_found} = Devices.mark_invalid("never-existed", "INVALID")
  end
end
