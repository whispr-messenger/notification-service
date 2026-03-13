defmodule WhisprNotificationsWeb.SettingsController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Settings

  @doc """
  GET /api/v1/notifications/settings
  Returns the notification settings for the authenticated user.
  """
  def show(conn, params) do
    user_id = get_user_id(conn, params)

    case Settings.get_user_settings(user_id) do
      {:ok, settings} ->
        json(conn, %{
          user_id: settings.user_id,
          mute_all: settings.mute_all,
          message_notifications: settings.message_notifications,
          group_notifications: settings.group_notifications,
          contact_notifications: settings.contact_notifications
        })

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to retrieve settings"})
    end
  end

  @doc """
  PATCH /api/v1/notifications/settings
  Updates notification settings for the authenticated user.

  Accepted fields:
    - mute_all (boolean)
    - message_notifications (boolean)
    - group_notifications (boolean)
    - contact_notifications (boolean)
  """
  def update(conn, params) do
    user_id = get_user_id(conn, params)

    allowed_keys = ~w(mute_all message_notifications group_notifications contact_notifications)
    update_attrs = Map.take(params, allowed_keys)

    case Settings.update_user_settings(user_id, update_attrs) do
      {:ok, settings} ->
        json(conn, %{
          user_id: settings.user_id,
          mute_all: settings.mute_all,
          message_notifications: settings.message_notifications,
          group_notifications: settings.group_notifications,
          contact_notifications: settings.contact_notifications
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to update settings"})
    end
  end

  defp get_user_id(conn, params) do
    Map.get(params, "user_id") || get_req_header(conn, "x-user-id") |> List.first()
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
