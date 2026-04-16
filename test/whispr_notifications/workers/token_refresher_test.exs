defmodule WhisprNotifications.Workers.TokenRefresherTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Workers.TokenRefresher

  test "is started under the app supervisor and accepts :refresh_tokens" do
    pid = Process.whereis(TokenRefresher)
    assert is_pid(pid)
    assert Process.alive?(pid)

    send(pid, :refresh_tokens)
    assert :sys.get_state(pid) == %{}
  end
end
