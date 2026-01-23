defmodule WhisprNotifications.Workers.MetricsWorker do
  @moduledoc """
  Worker qui pousse des métriques / telemetry sur les notifications.
  """

  use GenServer

  @interval :timer.minutes(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule()
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    # Rapporter les métriques (nombre de notifs envoyées, échecs, etc.).
    schedule()
    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :tick, @interval)
  end
end
