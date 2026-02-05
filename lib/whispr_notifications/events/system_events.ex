defmodule WhisprNotifications.Events.SystemEvents do
  @moduledoc """
  Notifications système (maintenance, mot de passe, etc.).
  """

  alias WhisprNotifications.Notifications.{Notification, Filter, History}
  alias WhisprNotifications.Devices.CacheManager
  alias WhisprNotifications.Delivery.BatchProcessor

  @type system_event :: %{
          user_id: String.t(),
          code: String.t(),
          message: String.t()
        }

  @spec handle(system_event()) :: :ok
  def handle(event) do
    notif =
      Notification.new(%{
        user_id: event.user_id,
        type: :system,
        title: "Notification système",
        body: event.message,
        context: %{
          "code" => event.code
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
