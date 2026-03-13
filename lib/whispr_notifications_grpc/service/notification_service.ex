defmodule WhisprNotificationsGrpc.Service.NotificationService do
  @moduledoc """
  gRPC service for notification-specific operations.
  Provides RPC methods for other services to send notifications.
  """

  require Logger

  alias WhisprNotifications.Delivery.PushDispatcher

  @doc """
  Sends a push notification to a specific user.
  Called by other microservices via gRPC.
  """
  def send_notification(%{user_id: user_id, title: title, body: body} = request) do
    data = Map.get(request, :data, %{})
    type = Map.get(request, :type, :new_message)
    conversation_id = Map.get(request, :conversation_id)

    case PushDispatcher.dispatch(user_id, title, body, data,
           type: type,
           conversation_id: conversation_id
         ) do
      :ok ->
        {:ok, %{status: "sent"}}

      {:partial, sent, failed} ->
        {:ok, %{status: "partial", sent: sent, failed: failed}}

      {:error, reason} ->
        Logger.error("Failed to send notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a push notification to multiple users (batch).
  """
  def send_batch(%{user_ids: user_ids, title: title, body: body} = request) do
    data = Map.get(request, :data, %{})
    type = Map.get(request, :type, :new_message)

    results =
      Enum.map(user_ids, fn user_id ->
        {user_id, PushDispatcher.dispatch(user_id, title, body, data, type: type)}
      end)

    {:ok, %{results: results}}
  end
end
