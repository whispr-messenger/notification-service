defmodule WhisprNotifications.Workers.CacheSyncWorkerTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Workers.CacheSyncWorker

  test "is started under the app supervisor and handles :sync" do
    pid = Process.whereis(CacheSyncWorker)
    assert is_pid(pid)

    send(pid, :sync)
    assert :sys.get_state(pid) == %{}
  end
end
