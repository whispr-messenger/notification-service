defmodule WhisprNotifications.Workers.CleanupWorker do
  @moduledoc """
  Worker périodique qui nettoie l’historique de notifications (par ex. > 90 jours).
  """

  use GenServer

  alias WhisprNotifications.Notifications.History

  @interval :timer.hours(12)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Implémente la purge dans History plus tard
    _ = History
    schedule()
    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :cleanup, @interval)
  end
end
