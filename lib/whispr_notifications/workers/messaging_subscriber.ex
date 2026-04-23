defmodule WhisprNotifications.Workers.MessagingSubscriber do
  @moduledoc """
  Redis pub/sub subscriber for messaging events driving badge counts.

  - `whispr:messaging:new_message` → incr badge for every recipient
  - `whispr:messaging:message_read` → decr badge for the reader

  Payload contract (best effort, fields may be absent):

      %{
        "user_id" => "uuid",          # target user (read events)
        "target_user_ids" => [...],   # recipients (new_message fanout)
        "count" => 1                  # optional batch size
      }
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Badges
  alias WhisprNotifications.RedisConfig

  @channels [
    "whispr:messaging:new_message",
    "whispr:messaging:message_read"
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

        Logger.info("[MessagingSubscriber] Subscribed to #{length(@channels)} messaging channels")

        {:ok, %{pubsub: pubsub}}

      {:error, reason} ->
        Logger.error("[MessagingSubscriber] Failed to connect to Redis: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, 5_000)
        {:ok, %{pubsub: nil}}
    end
  end

  @impl true
  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :subscribed, %{channel: channel}},
        state
      ) do
    Logger.debug("[MessagingSubscriber] Subscribed to #{channel}")
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
    Logger.info("[MessagingSubscriber] Retrying Redis connection...")
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
          "[MessagingSubscriber] Ignoring non-object payload on #{channel}: #{inspect(other)}"
        )

      {:error, reason} ->
        Logger.error(
          "[MessagingSubscriber] Failed to decode payload on #{channel}: #{inspect(reason)}"
        )
    end
  rescue
    error ->
      Logger.error("[MessagingSubscriber] Error handling #{channel}: #{inspect(error)}")
  end

  @doc """
  Route un payload décodé vers l'action badge correspondante. Exposé pour les
  tests afin de tester la logique sans passer par Redis.
  """
  @spec process_message(String.t(), map()) :: :ok
  def process_message("whispr:messaging:new_message", payload) do
    count = positive_count(Map.get(payload, "count", 1))
    payload |> target_user_ids() |> Enum.each(&Badges.incr(&1, count))
    :ok
  end

  def process_message("whispr:messaging:message_read", payload) do
    count = positive_count(Map.get(payload, "count", 1))

    case Map.get(payload, "user_id") do
      user_id when is_binary(user_id) and user_id != "" ->
        Badges.decr(user_id, count)
        :ok

      _ ->
        :ok
    end
  end

  def process_message(channel, _payload) do
    Logger.warning("[MessagingSubscriber] Unknown channel: #{channel}")
    :ok
  end

  defp target_user_ids(payload) do
    case Map.get(payload, "target_user_ids") do
      list when is_list(list) ->
        Enum.filter(list, &(is_binary(&1) and &1 != ""))

      _ ->
        case Map.get(payload, "user_id") do
          id when is_binary(id) and id != "" -> [id]
          _ -> []
        end
    end
  end

  defp positive_count(n) when is_integer(n) and n > 0, do: n
  defp positive_count(_), do: 1
end
