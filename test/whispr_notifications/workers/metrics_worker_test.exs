defmodule WhisprNotifications.Workers.MetricsWorkerTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Workers.MetricsWorker

  test "is started under the app supervisor and handles :tick" do
    pid = Process.whereis(MetricsWorker)
    assert is_pid(pid)

    send(pid, :tick)
    assert :sys.get_state(pid) == %{}
  end
end
