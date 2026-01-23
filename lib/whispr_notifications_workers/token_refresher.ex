defmodule  WhisprNotifications.Workers.TokenRefresher do
  @moduledoc """
  Worker pour rafraîchir les tockens FCM/APNS invalides.
  """

  use GenServer

  @interval :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule()
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh_tokens, state) do
    # a implémenter: envoie erreur, tokens obsolètes, etc
    schedule()
    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :refresh_tokens, @interval)
  end
end
