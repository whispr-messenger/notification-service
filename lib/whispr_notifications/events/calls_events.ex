defmodule WhisprNotifications.Events.CallsEvents do
  @moduledoc """
  Handles call-related events originating from the calls-service.

  Each event triggers a WebSocket broadcast on `user:<id>` topics so connected
  clients can update their call UI in real time, and (when relevant) schedules
  a VoIP-style push notification via the standard notification pipeline so the
  target devices wake up on iOS/Android.

  Subscribed Redis channels:
  - whispr:calls:initiated
  - whispr:calls:accepted
  - whispr:calls:declined
  - whispr:calls:ended
  - whispr:calls:missed
  """

  require Logger

  alias WhisprNotifications.Notifications
  alias WhisprNotificationsWeb.Endpoint

  @spec handle_initiated(map()) :: :ok
  def handle_initiated(%{"participant_ids" => participants} = payload)
      when is_list(participants) do
    call_id = payload["call_id"]
    initiator_id = payload["initiator_id"]
    conversation_id = payload["conversation_id"]
    type = payload["type"] || "audio"

    data = %{
      "call_id" => call_id,
      "initiator_id" => initiator_id,
      "conversation_id" => conversation_id,
      "type" => type
    }

    participants
    |> Enum.filter(&is_binary/1)
    |> Enum.each(fn participant_id ->
      broadcast_to_user(participant_id, "incoming_call", data)

      if participant_id != initiator_id do
        send_voip_push(participant_id, %{
          title: "Incoming #{type} call",
          body: "Tap to answer",
          context:
            Map.merge(data, %{
              "event" => "call_initiated"
            })
        })
      end
    end)

    :ok
  end

  def handle_initiated(payload) do
    Logger.warning(
      "[CallsEvents] Skipping :initiated event — missing participant_ids: #{inspect(payload)}"
    )

    :ok
  end

  @spec handle_accepted(map()) :: :ok
  def handle_accepted(payload) do
    user_id = payload["user_id"]
    call_id = payload["call_id"]

    data = %{"call_id" => call_id, "user_id" => user_id}

    if is_binary(user_id), do: broadcast_to_user(user_id, "call_accepted", data)

    :ok
  end

  @spec handle_declined(map()) :: :ok
  def handle_declined(payload) do
    user_id = payload["user_id"]
    call_id = payload["call_id"]

    data = %{"call_id" => call_id, "user_id" => user_id}

    if is_binary(user_id), do: broadcast_to_user(user_id, "call_declined", data)

    :ok
  end

  @spec handle_ended(map()) :: :ok
  def handle_ended(payload) do
    call_id = payload["call_id"]
    duration = payload["duration_seconds"]
    reason = payload["end_reason"]
    participants = payload["participants"] || []

    data = %{
      "call_id" => call_id,
      "duration_seconds" => duration,
      "end_reason" => reason
    }

    participants
    |> Enum.filter(&is_binary/1)
    |> Enum.each(&broadcast_to_user(&1, "call_ended", data))

    :ok
  end

  @spec handle_missed(map()) :: :ok
  def handle_missed(payload) do
    user_id = payload["user_id"]
    call_id = payload["call_id"]

    data = %{"call_id" => call_id, "user_id" => user_id}

    if is_binary(user_id) do
      broadcast_to_user(user_id, "call_missed", data)

      send_voip_push(user_id, %{
        title: "Missed call",
        body: "You missed a call",
        context: Map.merge(data, %{"event" => "call_missed"})
      })
    end

    :ok
  end

  defp broadcast_to_user(user_id, event, data) do
    Endpoint.broadcast("user:#{user_id}", event, data)
  end

  defp send_voip_push(user_id, %{title: title, body: body, context: context}) do
    case Notifications.create(%{
           user_id: user_id,
           type: :system,
           title: title,
           body: body,
           context: context,
           metadata: %{"apns_push_type" => "voip", "priority" => "high"}
         }) do
      {:ok, _notif} ->
        :ok

      other ->
        Logger.warning(
          "[CallsEvents] VoIP push not delivered for user #{user_id}: #{inspect(other)}"
        )

        :ok
    end
  end
end
