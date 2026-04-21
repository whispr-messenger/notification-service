defmodule WhisprNotifications.Workers.ModerationSubscriber do
  @moduledoc """
  Redis pub/sub subscriber for moderation events.
  Listens to whispr:moderation:* channels and routes to ModerationEvents handlers.
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Events.ModerationEvents

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
    redis_config = Application.get_env(:whispr_notification, :redis, [])

    redis_opts =
      [
        host: Keyword.get(redis_config, :host, "localhost"),
        port: Keyword.get(redis_config, :port, 6379),
        database: Keyword.get(redis_config, :database, 0)
      ]
      |> maybe_put(:password, Keyword.get(redis_config, :password), &(&1 not in [nil, ""]))
      |> maybe_put(:timeout, Keyword.get(redis_config, :timeout), &is_integer/1)
      |> maybe_put(:ssl, Keyword.get(redis_config, :ssl), &is_boolean/1)

    case Redix.PubSub.start_link(redis_opts) do
      {:ok, pubsub} ->
        for channel <- @channels do
          Redix.PubSub.subscribe(pubsub, channel, self())
        end

        Logger.info(
          "[ModerationSubscriber] Subscribed to #{length(@channels)} moderation channels"
        )

        {:ok, %{pubsub: pubsub}}

      {:error, reason} ->
        Logger.error("[ModerationSubscriber] Failed to connect to Redis: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, 5_000)
        {:ok, %{pubsub: nil}}
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

  def handle_info(:retry_connect, state) do
    Logger.info("[ModerationSubscriber] Retrying Redis connection...")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

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

  defp maybe_put(opts, _key, nil, _valid?), do: opts

  defp maybe_put(opts, key, value, valid?) do
    if valid?.(value), do: Keyword.put(opts, key, value), else: opts
  end
end
