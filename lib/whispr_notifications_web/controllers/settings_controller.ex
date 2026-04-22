defmodule WhisprNotificationsWeb.SettingsController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Manager
  alias WhisprNotifications.Preferences.UserSettings

  # GET /api/settings/:id
  def show(conn, %{"id" => user_id}) do
    case Manager.get_user_settings(user_id) do
      {:ok, user_settings} -> json(conn, serialize(user_settings))
      _ -> send_resp(conn, 404, "")
    end
  end

  # PUT /api/settings/:id
  def update(conn, %{"id" => user_id} = params) do
    attrs = Map.drop(params, ["id"])

    case Manager.update_user_settings(user_id, attrs) do
      {:ok, %UserSettings{}} ->
        send_resp(conn, 204, "")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors(changeset)})
    end
  end

  defp serialize(%UserSettings{} = s) do
    %{
      user_id: s.user_id,
      language: s.language,
      timezone: s.timezone,
      message_push_enabled: s.message_push_enabled,
      message_email_enabled: s.message_email_enabled,
      system_push_enabled: s.system_push_enabled,
      marketing_push_enabled: s.marketing_push_enabled,
      quiet_hours_start: s.quiet_hours_start,
      quiet_hours_end: s.quiet_hours_end
    }
  end

  defp errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
