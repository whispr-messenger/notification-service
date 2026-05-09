defmodule WhisprNotifications.Workers.CallsSubscriber do
  @moduledoc """
  Redis pub/sub subscriber for call lifecycle events.

  Listens to `whispr:calls:*` channels emitted by the calls-service and
  forwards every event to the notification pipeline:

  - WebSocket broadcast on `user:<id>` topics so connected clients can update
    their call UI instantly
  - VoIP-style push notifications to wake up mobile devices

  The dispatch logic lives in `WhisprNotifications.Events.CallsEvents`; this
  module only owns the Redix PubSub connection and message routing.
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Events.CallsEvents
  alias WhisprNotifications.RedisConfig

  @channels [
    "whispr:calls:initiated",
    "whispr:calls:accepted",
    "whispr:calls:declined",
    "whispr:calls:ended",
    "whispr:calls:missed"
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[CallsSubscriber] Subscribed to #{length(@channels)} calls channels")
        {:ok, %{pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        Logger.error("[CallsSubscriber] Failed to connect to Redis: #{inspect(reason)}")
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
    Logger.debug("[CallsSubscriber] Subscribed to #{channel}")
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: channel, payload: raw_payload}},
        state
      ) do
    Task.start(fn -> handle_message(channel, raw_payload) end)
    {:noreply, state}
  end

  # arret explicite sur disconnect Redis pour laisser le Supervisor relancer
  # init/1 et re-souscrire les channels proprement
  def handle_info({:redix_pubsub, _pid, _ref, :disconnected, _meta}, state) do
    Logger.warning("[CallsSubscriber] Redis PubSub disconnected, restarting subscriber")
    {:stop, :redis_disconnected, state}
  end

  # backoff exponentiel borne a 60s pour eviter d'epuiser le budget de
  # restart du Supervisor lors d'une coupure Redis prolongee
  def handle_info(:retry_connect, %{retry_attempt: n} = state) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[CallsSubscriber] Reconnected to Redis after #{n} attempts")
        {:noreply, %{state | pubsub: pubsub, retry_attempt: 0}}

      {:error, reason} ->
        delay = backoff_delay(n)

        Logger.warning(
          "[CallsSubscriber] Redis reconnect failed, retry in #{delay}ms: #{inspect(reason)}"
        )

        Process.send_after(self(), :retry_connect, delay)
        {:noreply, %{state | pubsub: nil, retry_attempt: n + 1}}
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  # 1s, 2s, 4s, 8s, 16s, 32s, 60s plafond
  defp backoff_delay(n) when is_integer(n) and n >= 0 do
    min(60_000, trunc(1_000 * :math.pow(2, n)))
  end

  defp handle_message(channel, raw_payload) do
    case Jason.decode(raw_payload) do
      {:ok, payload} when is_map(payload) ->
        process_message(channel, payload)

      {:ok, other} ->
        Logger.warning(
          "[CallsSubscriber] Ignoring non-object payload on #{channel}: #{inspect(other)}"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "[CallsSubscriber] Failed to decode payload on #{channel}: #{inspect(reason)}"
        )

        :ok
    end
  rescue
    error ->
      Logger.error("[CallsSubscriber] Error handling #{channel}: #{inspect(error)}")
      :ok
  end

  @doc """
  Routes a decoded payload to the matching `CallsEvents` handler. Exposed so
  tests can exercise the dispatch logic directly without going through Redis.
  """
  @spec process_message(String.t(), map()) :: :ok
  def process_message("whispr:calls:initiated", payload),
    do: CallsEvents.handle_initiated(payload)

  def process_message("whispr:calls:accepted", payload),
    do: CallsEvents.handle_accepted(payload)

  def process_message("whispr:calls:declined", payload),
    do: CallsEvents.handle_declined(payload)

  def process_message("whispr:calls:ended", payload),
    do: CallsEvents.handle_ended(payload)

  def process_message("whispr:calls:missed", payload),
    do: CallsEvents.handle_missed(payload)

  def process_message(channel, _payload) do
    Logger.warning("[CallsSubscriber] Unknown channel: #{channel}")
    :ok
  end
end
