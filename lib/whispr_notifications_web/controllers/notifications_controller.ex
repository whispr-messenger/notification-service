defmodule WhisprNotificationsWeb.NotificationsController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Notifications
  alias WhisprNotifications.Notifications.Notification

  @doc """
  POST /api/v1/notifications

  Corps JSON attendu :
  - `user_id` (string, optionnel — doit être égal au `sub` du JWT si fourni ;
    sinon le `sub` du JWT est utilisé)
  - `type` : `"message"`, `"group"` ou `"system"`
  - `title`, `body` (string, requis)
  - `context` (objet JSON, défaut `{}`)
  - `conversation_id`, `metadata` (optionnels)

  Autorisation : un client authentifié ne peut créer de notification que pour
  lui-même. Tout `user_id` présent dans le body différent du `sub` du JWT est
  rejeté avec 403 (cf. WHISPR security audit §8).
  """
  def create(conn, params) do
    jwt_sub = conn.assigns[:jwt_sub]
    body_user_id = body_user_id(params)

    case authorize_user_id(jwt_sub, body_user_id) do
      {:ok, resolved_user_id} ->
        params
        |> Map.put("user_id", resolved_user_id)
        |> Notifications.create()
        |> render_create(conn)

      :forbidden ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden"})
    end
  end

  defp body_user_id(params) do
    case Map.get(params, "user_id") || Map.get(params, :user_id) do
      "" -> nil
      value -> value
    end
  end

  defp authorize_user_id(jwt_sub, nil) when is_binary(jwt_sub), do: {:ok, jwt_sub}
  defp authorize_user_id(jwt_sub, jwt_sub) when is_binary(jwt_sub), do: {:ok, jwt_sub}
  defp authorize_user_id(_jwt_sub, _body_user_id), do: :forbidden

  defp render_create({:ok, %Notification{} = notif}, conn) do
    conn
    |> put_status(:created)
    |> json(serialize(notif))
  end

  defp render_create({:error, :validation, errors}, conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: errors})
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
