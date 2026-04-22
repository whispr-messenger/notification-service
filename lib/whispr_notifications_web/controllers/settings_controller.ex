defmodule WhisprNotificationsWeb.SettingsController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Manager
  alias WhisprNotifications.Preferences.UserSettings

  # GET /api/settings/:id
  def show(conn, %{"id" => user_id}) when is_binary(user_id) and user_id != "" do
    render_settings(conn, user_id)
  end

  # GET /api/v1/settings — authenticated user from JWT
  def show(conn, _params) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        render_settings(conn, user_id)

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "missing_user"})
    end
  end

  # PUT /api/settings/:id
  def update(conn, %{"id" => user_id} = params)
      when is_binary(user_id) and user_id != "" do
    attrs = Map.drop(params, ["id"])
    do_update(conn, user_id, attrs)
  end

  # PUT /api/v1/settings — authenticated user from JWT
  def update(conn, params) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        do_update(conn, user_id, Map.drop(params, ["id"]))

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "missing_user"})
    end
  end

  defp render_settings(conn, user_id) do
    case Manager.get_user_settings(user_id) do
      {:ok, user_settings} -> json(conn, serialize(user_settings))
      _ -> send_resp(conn, 404, "")
    end
  end

  defp do_update(conn, user_id, attrs) do
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
