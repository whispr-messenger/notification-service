defmodule WhisprNotifications.Events.ContactEvents do
  @moduledoc """
  Handles contact-related events (contact requests, acceptances).
  Converts events into Notification structs and dispatches them.
  """

  alias WhisprNotifications.Notifications.{Notification, Filter, History}
  alias WhisprNotifications.Devices.CacheManager
  alias WhisprNotifications.Delivery.BatchProcessor

  @type contact_event :: %{
    user_id: String.t(),
    from_user_id: String.t(),
    from_username: String.t(),
    action: :request | :accepted
  }

  @spec handle(contact_event()) :: :ok
  def handle(event) do
    {title, body} =
      case event.action do
        :request ->
          {"Contact request",
           "#{Map.get(event, :from_username, "Someone")} sent you a contact request"}

        :accepted ->
          {"Contact accepted",
           "#{Map.get(event, :from_username, "Someone")} accepted your contact request"}
      end

    notif =
      Notification.new(%{
        user_id: event.user_id,
        type: :contact_request,
        title: title,
        body: body,
        context: %{
          "from_user_id" => event.from_user_id,
          "action" => Atom.to_string(event.action)
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
