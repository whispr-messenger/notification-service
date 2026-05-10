defmodule WhisprNotifications.Workers.InboxSubscriber do
  @moduledoc """
  Redis pub/sub subscriber pour les evenements inbox utilisateur.

  Ecoute le channel `whispr:notifications:inbox` et pour chaque message :
    1. Insere un item dans la table `notification_inbox` via `Inbox.insert/3`
    2. Broadcast l'item sur le topic WS `user:<user_id>` via Endpoint.broadcast/3

  Payload Redis attendu :
    %{
      "user_id"    => "<uuid>",
      "event_type" => "mention" | "reply" | "contact_request" | "missed_call",
      "payload"    => %{...}
    }
  """

  use GenServer
  require Logger

  alias WhisprNotifications.Inbox
  alias WhisprNotifications.RedisConfig
  alias WhisprNotificationsWeb.Endpoint

  @channel "whispr:notifications:inbox"
  @valid_event_types ~w(mention reply contact_request missed_call)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[InboxSubscriber] Subscribed to #{@channel}")
        {:ok, %{pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        Logger.error("[InboxSubscriber] Failed to connect to Redis: #{inspect(reason)}")
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
    Logger.debug("[InboxSubscriber] Subscribed to #{channel}")
    {:noreply, state}
  end

  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: @channel, payload: raw_payload}},
        state
      ) do
    Task.start(fn -> handle_message(raw_payload) end)
    {:noreply, state}
  end

  # arret explicite sur disconnect Redis pour laisser le Supervisor relancer
  def handle_info({:redix_pubsub, _pid, _ref, :disconnected, _meta}, state) do
    Logger.warning("[InboxSubscriber] Redis PubSub disconnected, restarting subscriber")
    {:stop, :redis_disconnected, state}
  end

  # backoff exponentiel borne a 60s
  def handle_info(:retry_connect, %{retry_attempt: n} = state) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[InboxSubscriber] Reconnected to Redis after #{n} attempts")
        {:noreply, %{state | pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        delay = backoff_delay(n)

        Logger.warning(
          "[InboxSubscriber] Redis reconnect failed, retry in #{delay}ms: #{inspect(reason)}"
        )

        Process.send_after(self(), :retry_connect, delay)
        {:noreply, %{state | pubsub: nil, retry_attempt: n + 1}}
        # coveralls-ignore-stop
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- logique de traitement ---

  @doc """
  Traite un payload Redis decode : insere dans l'inbox et broadcast WS.
  Expose pour les tests sans passer par Redis.
  """
  @spec process_message(map()) :: :ok
  def process_message(
        %{"user_id" => user_id, "event_type" => event_type, "payload" => payload} = _msg
      )
      when is_binary(user_id) and user_id != "" and is_binary(event_type) and is_map(payload) do
    if event_type in @valid_event_types do
      case Inbox.insert(user_id, event_type, payload) do
        {:ok, item} ->
          Endpoint.broadcast("user:#{user_id}", "inbox:new", item_to_map(item))

        {:error, changeset} ->
          Logger.error("[InboxSubscriber] Failed to insert inbox item: #{inspect(changeset)}")
      end
    else
      Logger.warning("[InboxSubscriber] Unknown event_type: #{inspect(event_type)}")
    end

    :ok
  end

  def process_message(msg) do
    Logger.warning("[InboxSubscriber] Malformed inbox message: #{inspect(msg)}")
    :ok
  end

  # --- helpers prive ---

  defp handle_message(raw_payload) do
    case Jason.decode(raw_payload) do
      {:ok, payload} when is_map(payload) ->
        process_message(payload)

      {:ok, other} ->
        Logger.warning("[InboxSubscriber] Ignoring non-object payload: #{inspect(other)}")
        :ok

      {:error, reason} ->
        Logger.error("[InboxSubscriber] Failed to decode payload: #{inspect(reason)}")
        :ok
    end
  rescue
    error ->
      Logger.error("[InboxSubscriber] Error handling message: #{inspect(error)}")
      :ok
  end

  defp connect_pubsub do
    case Redix.PubSub.start_link(RedisConfig.build()) do
      {:ok, pubsub} ->
        Redix.PubSub.subscribe(pubsub, @channel, self())
        {:ok, pubsub}

      # coveralls-ignore-start
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

  defp item_to_map(item) do
    %{
      id: item.id,
      user_id: item.user_id,
      event_type: item.event_type,
      payload: item.payload,
      read_at: format_dt(item.read_at),
      created_at: format_dt(item.created_at)
    }
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(nil), do: nil
end
