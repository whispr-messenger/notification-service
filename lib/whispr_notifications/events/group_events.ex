defmodule WhisprNotifications.Events.GroupEvents do
  @moduledoc """
  Événements liés aux groupes (ajout, changement de rôle, etc).
  """

  alias WhisprNotifications.Notifications.{Notification, Filter, History}
  alias WhisprNotifications.Devices.CacheManager
  alias WhisprNotifications.Delivery.BatchProcessor

  @type group_event :: %{
    user_id: String.t(),
    group_id: String.t(),
    actor_id: String.t(),
    action: :added | :removed | :role_changed
  }

  @spec handle(group_event()) :: :ok
  def handle(event) do
    {title, body} =
      case event.action do
        :added -> {"Ajouté au groupe", "Vous avez été ajouté à un groupe"}
        :removed -> {"Retiré de groupe", "Vous avez été retiré d'un groupe"}
        :role_changed -> {"Rôle mis à jour", "Votre rôle dans le groupe a changé"}
      end
    notif =
      Notification.new(%{
        user_id: event.user_id,
        type: :group,
        title: title,
        body: body,

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
