defmodule WhisprNotificationsWeb.BadgeController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Badges

  @doc """
  GET /api/v1/badge

  Retourne le compteur de badge courant pour l'utilisateur authentifié,
  utilisé par les apps mobiles au cold-start pour synchroniser l'icône.
  """
  def show(conn, _params) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        json(conn, %{unread_count: Badges.get(user_id)})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "missing_user"})
    end
  end
end
