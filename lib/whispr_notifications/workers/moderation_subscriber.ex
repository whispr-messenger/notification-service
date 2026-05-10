defmodule WhisprNotifications.Workers.ModerationSubscriber do
  @moduledoc """
  Redis pub/sub subscriber for moderation events.
  Listens to whispr:moderation:* channels and routes to ModerationEvents handlers.
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Events.ModerationEvents
  alias WhisprNotifications.RedisConfig

  @channels [
    "whispr:moderation:report_created",
    "whispr:moderation:sanction_applied",
    "whispr:moderation:sanction_lifted",
    "whispr:moderation:appeal_created",
    "whispr:moderation:appeal_resolved",
    "whispr:moderation:threshold_reached",
    "whispr:moderation:blocked_image_approved",
    "whispr:moderation:blocked_image_rejected"
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info(
          "[ModerationSubscriber] Subscribed to #{length(@channels)} moderation channels"
        )

        {:ok, %{pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        Logger.error("[ModerationSubscriber] Failed to connect to Redis: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, 1_000)
        {:ok, %{pubsub: nil, retry_attempt: 1}}
        # coveralls-ignore-stop
    end
  end

  @impl true
  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :subscribed, %{channel: channel}},
        state
      ) do
    Logger.debug("[ModerationSubscriber] Subscribed to #{channel}")
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: channel, payload: payload}},
        state
      ) do
    Task.start(fn ->
      handle_message(channel, payload)
    end)

    {:noreply, state}
  end

  # arret explicite sur disconnect Redis pour laisser le Supervisor relancer
  # init/1 et re-souscrire les channels proprement
  def handle_info({:redix_pubsub, _pid, _ref, :disconnected, _meta}, state) do
    Logger.warning("[ModerationSubscriber] Redis PubSub disconnected, restarting subscriber")
    {:stop, :redis_disconnected, state}
  end

  # backoff exponentiel borne a 60s pour eviter d'epuiser le budget de
  # restart du Supervisor lors d'une coupure Redis prolongee
  def handle_info(:retry_connect, %{retry_attempt: n} = state) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[ModerationSubscriber] Reconnected to Redis after #{n} attempts")
        {:noreply, %{state | pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        delay = backoff_delay(n)

        Logger.warning(
          "[ModerationSubscriber] Redis reconnect failed, retry in #{delay}ms: #{inspect(reason)}"
        )

        Process.send_after(self(), :retry_connect, delay)
        {:noreply, %{state | pubsub: nil, retry_attempt: n + 1}}
        # coveralls-ignore-stop
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ouvre la connexion Redix PubSub et souscrit aux channels declares
  defp connect_pubsub do
    case Redix.PubSub.start_link(RedisConfig.build()) do
      {:ok, pubsub} ->
        for channel <- @channels do
          Redix.PubSub.subscribe(pubsub, channel, self())
        end

        {:ok, pubsub}

      # coveralls-ignore-start — Redis injoignable, branche difficile a exercer en CI
      {:error, reason} ->
        {:error, reason}
        # coveralls-ignore-stop
    end
  end

  # 1s, 2s, 4s, 8s, 16s, 32s, 60s plafond
  # coveralls-ignore-start
  defp backoff_delay(n) when is_integer(n) and n >= 0 do
    min(60_000, trunc(1_000 * :math.pow(2, n)))
  end

  # coveralls-ignore-stop

  defp handle_message(channel, raw_payload) do
    case Jason.decode(raw_payload) do
      {:ok, payload} ->
        route_event(channel, payload)

      {:error, reason} ->
        Logger.error(
          "[ModerationSubscriber] Failed to decode payload on #{channel}: #{inspect(reason)}"
        )
    end
  rescue
    error ->
      Logger.error("[ModerationSubscriber] Error handling #{channel}: #{inspect(error)}")
  end

  defp route_event("whispr:moderation:report_created", payload),
    do: ModerationEvents.handle_report_created(payload)

  defp route_event("whispr:moderation:sanction_applied", payload),
    do: ModerationEvents.handle_sanction_applied(payload)

  defp route_event("whispr:moderation:sanction_lifted", payload),
    do: ModerationEvents.handle_sanction_lifted(payload)

  defp route_event("whispr:moderation:appeal_created", payload),
    do: ModerationEvents.handle_appeal_created(payload)

  defp route_event("whispr:moderation:appeal_resolved", payload),
    do: ModerationEvents.handle_appeal_resolved(payload)

  defp route_event("whispr:moderation:threshold_reached", payload),
    do: ModerationEvents.handle_threshold_warning(payload)

  defp route_event("whispr:moderation:blocked_image_approved", payload),
    do: ModerationEvents.handle_blocked_image_decision(payload, "approved")

  defp route_event("whispr:moderation:blocked_image_rejected", payload),
    do: ModerationEvents.handle_blocked_image_decision(payload, "rejected")

  defp route_event(channel, _payload),
    do: Logger.warning("[ModerationSubscriber] Unknown channel: #{channel}")
end
