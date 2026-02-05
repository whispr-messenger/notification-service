defmodule WhisprNotifications.Events.MessageEvents do
  @moduledoc """
  Gestion des évènements liés aux messages (nouveau message, mention, etc.).
  Convertit un évènement en Notification et le déclenche.
  """

  alias WhisprNotifications.Notifications.{Notification, Filter, History}
  alias WhisprNotifications.Devices.CacheManager
  alias WhisprNotifications.Delivery.BatchProcessor

  @type message_event :: %{
    user_id: String.t(),
    conversation_id: String.t(),
    message_id: String.t(),
    sender_id: String.t(),
    preview: String.t()
  }

  @spec handle_new_message(message_event()) :: :ok
  def handle_new_message(event) do
    notif =
      Notification.new(%{
        user_id: event.conversation_id,
        conversation_id: event.conversation_id,
        type: :message,
        title: "Nouveau message",
        body: event.preview,
        context: %{
          "message_id" => event.manager_id,
          "sender_id" => event.sender_id
        }
      })

      if Filter.should_send?(notif) do
        {:ok, cache} = CacheManager.get_cache(event.user_id)
        :ok = BatchProcessor.deliver(notif, cache)
        :ok = History.save(notif)
      else
        :ok
      end
  end
end
