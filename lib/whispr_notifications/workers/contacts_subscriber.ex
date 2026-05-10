defmodule WhisprNotifications.Workers.ContactsSubscriber do
  @moduledoc """
  Redis pub/sub subscriber for contact events. Drives push notifications
  for contact requests sent by the user-service.

  Channels:
    - `whispr:contacts:request_received` → push to the recipient
    - `whispr:contacts:request_accepted` → push back to the original requester

  Payload contract (best effort, fields may be absent):

      # request_received
      %{
        "user_id" => "uuid",                  # recipient (target of the push)
        "requester_id" => "uuid",             # who sent the request
        "requester_display_name" => "Alice",  # human-readable name (clear)
        "request_id" => "uuid"                # ContactRequest.id (deep-link)
      }

      # request_accepted
      %{
        "user_id" => "uuid",                  # original requester (target of the push)
        "accepter_id" => "uuid",              # who accepted
        "accepter_display_name" => "Bob",
        "request_id" => "uuid"
      }
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Events.ContactEvents
  alias WhisprNotifications.RedisConfig

  @channels [
    "whispr:contacts:request_received",
    "whispr:contacts:request_accepted"
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[ContactsSubscriber] Subscribed to #{length(@channels)} contact channels")
        {:ok, %{pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        Logger.error("[ContactsSubscriber] Failed to connect to Redis: #{inspect(reason)}")
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
    Logger.debug("[ContactsSubscriber] Subscribed to #{channel}")
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: channel, payload: raw_payload}},
        state
      ) do
    Task.start(fn -> process_message(channel, raw_payload) end)
    {:noreply, state}
  end

  # arret explicite sur disconnect Redis pour laisser le Supervisor relancer
  # init/1 et re-souscrire les channels proprement
  def handle_info({:redix_pubsub, _pid, _ref, :disconnected, _meta}, state) do
    Logger.warning("[ContactsSubscriber] Redis PubSub disconnected, restarting subscriber")
    {:stop, :redis_disconnected, state}
  end

  # backoff exponentiel borne a 60s pour eviter d'epuiser le budget de
  # restart du Supervisor lors d'une coupure Redis prolongee
  def handle_info(:retry_connect, %{retry_attempt: n} = state) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[ContactsSubscriber] Reconnected to Redis after #{n} attempts")
        {:noreply, %{state | pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        delay = backoff_delay(n)

        Logger.warning(
          "[ContactsSubscriber] Redis reconnect failed, retry in #{delay}ms: #{inspect(reason)}"
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

  @doc false
  @spec process_message(String.t(), String.t()) :: :ok
  def process_message(channel, raw_payload) do
    case Jason.decode(raw_payload) do
      {:ok, payload} when is_map(payload) ->
        dispatch(channel, payload)

      _ ->
        Logger.warning("[ContactsSubscriber] Invalid JSON on #{channel}: #{inspect(raw_payload)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("[ContactsSubscriber] process_message raised: #{inspect(e)}")
      :ok
  end

  defp dispatch("whispr:contacts:request_received", payload) do
    ContactEvents.handle_request_received(%{
      user_id: Map.get(payload, "user_id"),
      requester_id: Map.get(payload, "requester_id"),
      requester_display_name: Map.get(payload, "requester_display_name"),
      request_id: Map.get(payload, "request_id")
    })
  end

  defp dispatch("whispr:contacts:request_accepted", payload) do
    ContactEvents.handle_request_accepted(%{
      user_id: Map.get(payload, "user_id"),
      accepter_id: Map.get(payload, "accepter_id"),
      accepter_display_name: Map.get(payload, "accepter_display_name"),
      request_id: Map.get(payload, "request_id")
    })
  end

  defp dispatch(channel, _payload) do
    Logger.warning("[ContactsSubscriber] Unknown channel: #{channel}")
    :ok
  end
end
