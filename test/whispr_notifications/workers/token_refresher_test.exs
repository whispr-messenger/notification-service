defmodule WhisprNotifications.Workers.TokenRefresherTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.Device
  alias WhisprNotifications.Workers.TokenRefresher

  @user "88888888-8888-4888-8888-000000000001"

  setup do
    previous_retention =
      Application.get_env(:whispr_notification, :token_refresher_retention_days)

    # 7-day window so we don't have to backdate far in the test.
    Application.put_env(:whispr_notification, :token_refresher_retention_days, 7)

    on_exit(fn ->
      if previous_retention do
        Application.put_env(
          :whispr_notification,
          :token_refresher_retention_days,
          previous_retention
        )
      else
        Application.delete_env(:whispr_notification, :token_refresher_retention_days)
      end
    end)

    :ok
  end

  defp insert_invalid_device(token, last_error_at) do
    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "dev-" <> token,
        fcm_token: token,
        platform: "android"
      })

    :ok = Devices.mark_invalid(token, "UNREGISTERED")

    # override last_error_at with the explicit value
    {1, _} =
      from(d in Device, where: d.fcm_token == ^token)
      |> Repo.update_all(set: [last_error_at: DateTime.truncate(last_error_at, :second)])
  end

  test "is started under the app supervisor and accepts :refresh_tokens" do
    pid = Process.whereis(TokenRefresher)
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "run_now/0 hard-deletes devices invalidated before the retention cutoff" do
    too_old = DateTime.add(DateTime.utc_now(), -30, :day)
    recent = DateTime.add(DateTime.utc_now(), -1, :day)

    insert_invalid_device("old-token", too_old)
    insert_invalid_device("recent-token", recent)

    assert %{deleted: deleted} = TokenRefresher.run_now()
    assert deleted >= 1

    tokens = Repo.all(from d in Device, select: d.fcm_token)
    refute "old-token" in tokens
    assert "recent-token" in tokens
  end

  test "leaves active (non-deleted) devices alone even if old" do
    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "alive",
        fcm_token: "alive-token",
        platform: "android"
      })

    # Artificially age it — but since it was never marked invalid,
    # TokenRefresher must leave it alone.
    long_ago = DateTime.add(DateTime.utc_now(), -60, :day) |> DateTime.truncate(:second)

    {1, _} =
      from(d in Device, where: d.fcm_token == "alive-token")
      |> Repo.update_all(set: [inserted_at: long_ago, updated_at: long_ago])

    TokenRefresher.run_now()

    reloaded = Repo.one(from d in Device, where: d.fcm_token == "alive-token")
    assert reloaded != nil
    assert is_nil(reloaded.deleted_at)
  end

  test "emits a telemetry gauge with active / invalid / deleted counts" do
    ref = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        "token-refresher-test-#{inspect(ref)}",
        [:whispr_notifications, :tokens, :gauge],
        fn _event, measurements, meta, _cfg ->
          send(test_pid, {:telemetry, measurements, meta})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach("token-refresher-test-#{inspect(ref)}") end)

    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "d-active",
        fcm_token: "tok-active",
        platform: "android"
      })

    {:ok, _} =
      Devices.upsert(%{
        user_id: @user,
        device_id: "d-invalid",
        fcm_token: "tok-invalid",
        platform: "android"
      })

    :ok = Devices.mark_invalid("tok-invalid", "UNREGISTERED")

    TokenRefresher.run_now()

    assert_receive {:telemetry, measurements, %{status: "snapshot"}}, 1_000
    assert measurements.active == 1
    assert measurements.invalid == 1
    assert measurements.deleted == 0
  end
end
