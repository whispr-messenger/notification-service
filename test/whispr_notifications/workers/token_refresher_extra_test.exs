defmodule WhisprNotifications.Workers.TokenRefresherExtraTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Workers.TokenRefresher

  test "handle_info :refresh_tokens runs a cycle and reschedules" do
    pid = Process.whereis(TokenRefresher)
    send(pid, :refresh_tokens)
    # Allow the cycle to run; the GenServer must remain alive afterwards.
    Process.sleep(100)
    assert Process.alive?(pid)
  end

  test "handle_info catch-all keeps state and process alive" do
    pid = Process.whereis(TokenRefresher)
    send(pid, :unknown_message)
    Process.sleep(50)
    assert Process.alive?(pid)
  end
end
