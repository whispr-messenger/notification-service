defmodule WhisprNotifications.NotificationsExtraTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Notifications

  test "create/1 rejects an unknown atom type with a validation error" do
    assert {:error, :validation, errors} =
             Notifications.create(%{
               user_id: "u-bad-type",
               type: :foo,
               title: "t",
               body: "b"
             })

    assert Enum.any?(errors, &String.contains?(&1, "type"))
  end

  test "create/1 normalises a non-map context to an empty map" do
    assert {:ok, notif} =
             Notifications.create(%{
               user_id: "u-no-ctx",
               type: :system,
               title: "t",
               body: "b",
               context: "not-a-map"
             })

    assert notif.context == %{}
  end
end
