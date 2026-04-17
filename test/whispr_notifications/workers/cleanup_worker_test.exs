defmodule WhisprNotifications.Workers.CleanupWorkerTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Workers.CleanupWorker

  test "is started under the app supervisor and handles :cleanup" do
    pid = Process.whereis(CleanupWorker)
    assert is_pid(pid)

    send(pid, :cleanup)
    assert :sys.get_state(pid) == %{}
  end
end
