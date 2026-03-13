defmodule WhisprNotificationsGrpc.Service.EventService do
  @moduledoc """
  gRPC service that receives notification events from other microservices
  (messaging-service, user-service, etc.) and dispatches push notifications.
  """

  require Logger

  alias WhisprNotifications.Delivery.PushDispatcher
  alias WhisprNotifications.Events.{MessageEvents, GroupEvents, SystemEvents}

  @doc """
  Handles a new message event from the messaging-service.
  Triggers a push notification of type :new_message.
  """
  def handle_new_message(event) do
    Logger.info("Received new_message event for user #{event.user_id}")

    MessageEvents.handle_new_message(event)

    PushDispatcher.dispatch(
      event.user_id,
      "New message",
      event[:preview] || "You have a new message",
      %{
        "message_id" => event[:message_id],
        "sender_id" => event[:sender_id],
        "conversation_id" => event[:conversation_id]
      },
      type: :new_message,
      conversation_id: event[:conversation_id]
    )
  end

  @doc """
  Handles a group invite event.
  Triggers a push notification of type :group_invite.
  """
  def handle_group_invite(event) do
    Logger.info("Received group_invite event for user #{event.user_id}")

    GroupEvents.handle(%{
      user_id: event.user_id,
      group_id: event[:group_id],
      actor_id: event[:actor_id],
      action: :added
    })

    PushDispatcher.dispatch(
      event.user_id,
      "Group invitation",
      event[:message] || "You have been invited to a group",
      %{
        "group_id" => event[:group_id],
        "actor_id" => event[:actor_id]
      },
      type: :group_invite
    )
  end

  @doc """
  Handles a contact request event.
  Triggers a push notification of type :contact_request.
  """
  def handle_contact_request(event) do
    Logger.info("Received contact_request event for user #{event.user_id}")

    SystemEvents.handle(%{
      user_id: event.user_id,
      code: "contact_request",
      message: event[:message] || "You have a new contact request"
    })

    PushDispatcher.dispatch(
      event.user_id,
      "Contact request",
      event[:message] || "You have a new contact request",
      %{
        "from_user_id" => event[:from_user_id]
      },
      type: :contact_request
    )
  end

  @doc """
  Generic event handler that routes based on event type.
  This is the main entry point for gRPC calls from other services.
  """
  def handle_event(%{type: type} = event) do
    case type do
      :new_message -> handle_new_message(event)
      :group_invite -> handle_group_invite(event)
      :contact_request -> handle_contact_request(event)
      _ ->
        Logger.warning("Unknown event type: #{inspect(type)}")
        {:error, :unknown_event_type}
    end
  end

  def handle_event(%{"type" => type} = event) do
    atom_type = String.to_existing_atom(type)
    handle_event(Map.put(event, :type, atom_type) |> Map.delete("type"))
  rescue
    ArgumentError ->
      Logger.warning("Unknown event type string: #{type}")
      {:error, :unknown_event_type}
  end
end
