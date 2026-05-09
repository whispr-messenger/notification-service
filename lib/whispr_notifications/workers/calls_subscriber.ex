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
    case Redix.PubSub.start_link(RedisConfig.build()) do
      {:ok, pubsub} ->
        for channel <- @channels do
          Redix.PubSub.subscribe(pubsub, channel, self())
        end

        Logger.info("[CallsSubscriber] Subscribed to #{length(@channels)} calls channels")

        {:ok, %{pubsub: pubsub}}

      # coveralls-ignore-start
      {:error, reason} ->
        Logger.error("[CallsSubscriber] Failed to connect to Redis: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, 5_000)
        {:ok, %{pubsub: nil}}
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

  def handle_info(:retry_connect, state) do
    Logger.info("[CallsSubscriber] Retrying Redis connection...")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
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
