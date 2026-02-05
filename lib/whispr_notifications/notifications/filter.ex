defmodule WhisprNotifications.Notifications.Filter do
  @moduledoc """
  Logique de filtrage de notifications avant envoi (préférences, type, etc.).
  """

  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotifications.Preferences.Manager, as: PrefManager

  @spec should_send?(Notification.t(), DateTime.t()) :: boolean()
  def should_send?(%Notification{} = notif, now \\ DateTime.utc_now()) do
    PrefManager.allowed_for_notification?(notif, now)
  end
end
