defmodule WhisprNotificationsWeb.MuteController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Settings

  @doc """
  POST /api/v1/conversations/:id/mute
  Mutes notifications for a specific conversation.

  Optional body:
    { "muted_until": "2026-04-01T00:00:00Z" }
  """
  def mute(conn, %{"id" => conversation_id} = params) do
    user_id = get_user_id(conn, params)

    opts =
      case params["muted_until"] do
        nil -> %{}
        until -> %{muted_until: until}
      end

    case Settings.mute_conversation(user_id, conversation_id, opts) do
      {:ok, mute} ->
        conn
        |> put_status(:created)
        |> json(%{
          conversation_id: mute.conversation_id,
          muted: true,
          muted_until: mute.muted_until
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/conversations/:id/mute
  Unmutes notifications for a specific conversation.
  """
  def unmute(conn, %{"id" => conversation_id} = params) do
    user_id = get_user_id(conn, params)

    case Settings.unmute_conversation(user_id, conversation_id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
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
