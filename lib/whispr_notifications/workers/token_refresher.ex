defmodule WhisprNotifications.Workers.TokenRefresher do
  @moduledoc """
  Worker périodique de nettoyage des tokens FCM/APNS invalides.

  À chaque tick (toutes les heures par défaut, configurable) :

    * liste les devices soft-deletés par `Devices.mark_invalid/2` dont
      la dernière erreur date d'avant le cutoff de rétention (30 jours
      par défaut),
    * les supprime définitivement via `Devices.hard_delete/1`,
    * émet un événement telemetry `[:whispr_notifications, :tokens,
      :gauge]` avec les compteurs `active` / `invalid` pour alimenter
      la métrique Prometheus `notification_tokens_total{status}` (le
      bridge `telemetry → prom_ex` sera ajouté dans un ticket
      d'observabilité séparé — pour l'instant les valeurs sont aussi
      loggées pour ne pas perdre la trace).

  Config (voir `config/runtime.exs` / `config.exs`) :

    * `:token_refresher_interval_ms` — période du scan, défaut 1h.
    * `:token_refresher_retention_days` — âge min d'une ligne invalide
      avant purge, défaut 30 jours.
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Devices

  @default_interval :timer.hours(1)
  @default_retention_days 30
  @telemetry_event [:whispr_notifications, :tokens, :gauge]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{last_run: nil, deleted: 0}}
  end

  @impl true
  def handle_info(:refresh_tokens, state) do
    new_state = run_cycle(state)
    schedule()
    {:noreply, new_state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @doc """
  Exécute un cycle immédiatement (utile pour les tests et pour un
  déclenchement manuel via iex).
  """
  @spec run_now() :: %{deleted: non_neg_integer()}
  def run_now do
    GenServer.call(__MODULE__, :run_now)
  end

  @impl true
  def handle_call(:run_now, _from, state) do
    new_state = run_cycle(state)
    {:reply, %{deleted: new_state.deleted}, new_state}
  end

  # ----- internals -------------------------------------------------------

  defp run_cycle(state) do
    retention_days = retention_days()
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

    deleted =
      cutoff
      |> Devices.list_invalidated_before()
      |> Enum.reduce(0, fn device, acc ->
        {count, _} = Devices.hard_delete(device.id)
        acc + count
      end)

    emit_gauge(deleted)

    Logger.info(
      "[TokenRefresher] cycle done — deleted=#{deleted} cutoff=#{DateTime.to_iso8601(cutoff)}"
    )

    %{state | last_run: DateTime.utc_now(), deleted: deleted}
    # coveralls-ignore-start
  rescue
    e ->
      Logger.error("[TokenRefresher] cycle raised: #{inspect(e)}")
      state
      # coveralls-ignore-stop
  end

  defp emit_gauge(deleted) do
    %{active: active, invalid: invalid} = Devices.count_by_status()

    :telemetry.execute(
      @telemetry_event,
      %{active: active, invalid: invalid, deleted: deleted},
      %{status: "snapshot"}
    )

    Logger.info(
      "[TokenRefresher] notification_tokens " <>
        "active=#{active} invalid=#{invalid} deleted=#{deleted}"
    )
  end

  defp schedule do
    Process.send_after(self(), :refresh_tokens, interval_ms())
  end

  defp interval_ms do
    Application.get_env(:whispr_notification, :token_refresher_interval_ms, @default_interval)
  end

  defp retention_days do
    Application.get_env(
      :whispr_notification,
      :token_refresher_retention_days,
      @default_retention_days
    )
  end
end
