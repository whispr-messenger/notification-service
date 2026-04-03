defmodule WhisprNotificationsWeb.NotificationsController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Notifications
  alias WhisprNotifications.Notifications.Notification

  @doc """
  POST /api/v1/notifications

  Corps JSON attendu :
  - `user_id` (string, requis)
  - `type` : `"message"`, `"group"` ou `"system"`
  - `title`, `body` (string, requis)
  - `context` (objet JSON, défaut `{}`)
  - `conversation_id`, `metadata` (optionnels)
  """
  def create(conn, params) do
    case Notifications.create(params) do
      {:ok, %Notification{} = notif} ->
        conn
        |> put_status(:created)
        |> json(serialize(notif))

      {:error, :validation, errors} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: errors})
    end
  end

  defp serialize(%Notification{} = n) do
    %{
      id: n.id,
      user_id: n.user_id,
      type: Atom.to_string(n.type),
      title: n.title,
      body: n.body,
      conversation_id: n.conversation_id,
      created_at: format_dt(n.created_at)
    }
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(_), do: nil
end
