defmodule WhisprNotifications.Workers.CacheSyncWorker do
  @moduledoc """
  Worker pour synchroniser le cache de devices périodiquement ou en bulk.
  """

  use GenServer

  alias WhisprNotifications.Devices.CacheManager

  @interval :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule()
    {:ok, state}
  end

  @impl true
  def handle_info(:sync, state) do
    # Ici tu peux itérer sur les users à sync, ou réagir à des events externes.
    _ = CacheManager
    schedule()
    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :sync, @interval)
  end
end
