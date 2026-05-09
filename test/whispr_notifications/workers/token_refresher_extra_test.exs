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

  test "init stores a timer_ref in state" do
    pid = Process.whereis(TokenRefresher)
    state = :sys.get_state(pid)

    assert is_reference(state.timer_ref)
    # le timer doit etre encore vivant : Process.read_timer renvoie ms restants
    # ou false si le timer n'existe plus.
    assert is_integer(Process.read_timer(state.timer_ref))
  end

  test "terminate/2 cancels the pending timer" do
    # appel direct du callback : l'instance singleton ne doit pas etre tuee
    # juste pour ce test. on simule avec un ref de timer fraichement cree.
    timer_ref = Process.send_after(self(), :unused, 60_000)
    assert is_integer(Process.read_timer(timer_ref))

    assert :ok = TokenRefresher.terminate(:shutdown, %{timer_ref: timer_ref})

    # apres cancel, read_timer renvoie false.
    assert Process.read_timer(timer_ref) == false
  end

  test "terminate/2 without timer_ref returns :ok" do
    assert :ok = TokenRefresher.terminate(:shutdown, %{})
  end
end
