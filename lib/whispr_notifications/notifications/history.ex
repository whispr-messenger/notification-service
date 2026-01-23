defmodule WhisprNotifications.Notifications.History do
  @moduledoc """
  Gestion de l'historique des notifications (persistance, requêtes).
  """

  alias WhisprNotifications.Notifications.Notification

  defmodule Behaviour do
    @callback save(Notification.t()) :: :ok | {:error, term()}
    @callback mark_read(String.t(), DateTime.t()) :: :ok | {:error, term()}
    @callback list_for_user(String.t(), keyword()) :: [Notification.t()]
  end

  @behaviour Behaviour

  @impl true
  def save(_notif), do: :ok

  @impl true
  def mark_read(_id, _at), do: :ok

  @impl true
  def list_for_user(_user_id, _opts \\ []), do: []
end
