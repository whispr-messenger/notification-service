defmodule WhisprNotifications.Workers.MessagingSubscriber do
  @moduledoc """
  Redis pub/sub subscriber for messaging events driving badge counts.

  - `whispr:messaging:new_message` → incr badge for every recipient
  - `whispr:messaging:message_read` → decr badge for the reader

  Payload contract (best effort, fields may be absent):

      %{
        "user_id" => "uuid",            # target user (read events)
        "target_user_ids" => [...],     # recipients (new_message fanout)
        "mentioned_user_ids" => [...],  # subset of recipients that were @-mentioned
                                        # (publisher must populate; body is E2EE so the
                                        # server cannot derive mentions itself)
        "count" => 1                    # optional batch size
      }
  """

  use GenServer
  require Logger

  alias WhisprNotifications.{Badges, RedisConfig}
  alias WhisprNotifications.Delivery.BatchProcessor
  alias WhisprNotifications.Devices.AuthClient
  alias WhisprNotifications.Notifications.{Filter, History, Notification}

  @channels [
    "whispr:messaging:new_message",
    "whispr:messaging:message_read"
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[MessagingSubscriber] Subscribed to #{length(@channels)} messaging channels")
        {:ok, %{pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        Logger.error("[MessagingSubscriber] Failed to connect to Redis: #{inspect(reason)}")
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

  # arret explicite sur disconnect Redis pour laisser le Supervisor relancer
  # init/1 et re-souscrire les channels proprement
  def handle_info({:redix_pubsub, _pid, _ref, :disconnected, _meta}, state) do
    Logger.warning("[MessagingSubscriber] Redis PubSub disconnected, restarting subscriber")
    {:stop, :redis_disconnected, state}
  end

  # backoff exponentiel borne a 60s pour eviter d'epuiser le budget de
  # restart du Supervisor lors d'une coupure Redis prolongee
  def handle_info(:retry_connect, %{retry_attempt: n} = state) do
    case connect_pubsub() do
      {:ok, pubsub} ->
        Logger.info("[MessagingSubscriber] Reconnected to Redis after #{n} attempts")
        {:noreply, %{state | pubsub: pubsub, retry_attempt: 0}}

      # coveralls-ignore-start
      {:error, reason} ->
        delay = backoff_delay(n)

        Logger.warning(
          "[MessagingSubscriber] Redis reconnect failed, retry in #{delay}ms: #{inspect(reason)}"
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

      # coveralls-ignore-next-line — Redis injoignable, branche difficile a exercer en CI
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
  Route un payload décodé vers l'action badge + dispatch push
  correspondante. Exposé pour les tests afin de tester la logique sans
  passer par Redis.
  """
  @spec process_message(String.t(), map()) :: :ok
  def process_message("whispr:messaging:new_message", payload) do
    count = positive_count(Map.get(payload, "count", 1))
    recipients = target_user_ids(payload)
    mentioned = mentioned_user_ids(payload)

    Enum.each(recipients, fn user_id ->
      Badges.incr(user_id, count)
      dispatch_push(user_id, payload, user_id in mentioned)
    end)

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

  defp mentioned_user_ids(payload) do
    case Map.get(payload, "mentioned_user_ids") do
      list when is_list(list) -> Enum.filter(list, &(is_binary(&1) and &1 != ""))
      _ -> []
    end
  end

  defp positive_count(n) when is_integer(n) and n > 0, do: n
  defp positive_count(_), do: 1

  # Dispatch FCM/APNS push to every active device of `user_id`. Le
  # contenu texte est chiffré E2EE côté client, donc on envoie un body
  # générique basé sur `message_type` — le client déchiffre en
  # foreground et remplace par le vrai texte au tap.
  #
  # On tape directement AuthClient.fetch_devices pour avoir la liste
  # fraîche côté base ; CacheManager (qui fait du cache en mémoire)
  # pourrait rater un device fraîchement enregistré via POST /devices.
  defp dispatch_push(user_id, payload, mentioned?)
       when is_binary(user_id) and user_id != "" and is_boolean(mentioned?) do
    notif =
      Notification.new(%{
        user_id: user_id,
        type: :message,
        title: Map.get(payload, "sender_name") || "Nouveau message",
        body: body_for_type(Map.get(payload, "message_type")),
        conversation_id: Map.get(payload, "conversation_id"),
        context: %{
          "conversation_id" => Map.get(payload, "conversation_id"),
          "message_id" => Map.get(payload, "message_id"),
          "sender_id" => Map.get(payload, "sender_id")
        },
        metadata: %{"mentioned" => mentioned?}
      })

    :ok = History.save(notif)

    if Filter.should_send?(notif) do
      case AuthClient.fetch_devices(user_id) do
        {:ok, cache} -> BatchProcessor.deliver(notif, cache)
        # coveralls-ignore-next-line — defensive fallback, fetch_devices currently always returns {:ok, _} from a healthy DB
        _ -> :ok
      end
    else
      :ok
    end
  rescue
    e ->
      Logger.warning("[MessagingSubscriber] dispatch_push raised: #{inspect(e)}")
      :ok
  end

  # coveralls-ignore-next-line — guard catch-all, only callers pass binary user_id and boolean mentioned?
  defp dispatch_push(_user_id, _payload, _mentioned?), do: :ok

  defp body_for_type("photo"), do: "📷 Photo"
  defp body_for_type("voice"), do: "🎤 Message vocal"
  defp body_for_type("video"), do: "🎥 Vidéo"
  defp body_for_type("file"), do: "📎 Fichier"
  defp body_for_type("location"), do: "📍 Localisation"
  defp body_for_type(_), do: "Nouveau message"
end
