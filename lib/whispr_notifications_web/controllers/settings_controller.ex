defmodule WhisprNotificationsWeb.SettingsController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Manager

  # GET /api/settings/:user_id
  def show(conn, %{"user_id" => user_id}) do
    with {:ok, user_settings} <- Manager.get_user_settings(user_id) do
      json(conn, %{
        user_id: user_settings.user_id,
        message_push_enabled: user_settings.message_push_enabled,
        message_email_enabled: user_settings.message_email_enabled,
        system_push_enabled: user_settings.system_push_enabled,
        marketing_push_enabled: user_settings.marketing_push_enabled,
        quiet_hours_start: user_settings.quiet_hours_start,
        quiet_hours_end: user_settings.quiet_hours_end
      })
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # PUT /api/settings/:user_id
  # Pour l’instant on renvoie du stub, tu brancheras sur ton stockage réel
  def update(conn, %{"user_id" => user_id} = params) do
    # TODO: persister les settings et renvoyer le nouvel état
    _ = {user_id, params}
    send_resp(conn, 204, "")
  end
end
