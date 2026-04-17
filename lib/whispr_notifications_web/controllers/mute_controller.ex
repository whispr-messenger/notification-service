defmodule WhisprNotificationsWeb.MuteController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Manager

  # POST /api/conversations/:conversation_id/mute
  # user_id: peut être fourni en param, sinon dérivé du JWT sub.
  # Body/query params: mute_until (optionnel, ISO8601).
  def mute(conn, %{"conversation_id" => conversation_id} = params) do
    with {:ok, user_id} <- resolve_user_id(conn, params),
         {:ok, opts} <- build_opts(params) do
      case Manager.set_muted(user_id, conversation_id, true, opts) do
        {:ok, _} -> send_resp(conn, 204, "")
        {:error, changeset} -> unprocessable(conn, changeset)
      end
    else
      {:error, :missing_user_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: %{user_id: ["is required"]}})

      {:error, :invalid_datetime} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: %{mute_until: ["must be ISO8601"]}})
    end
  end

  # DELETE /api/conversations/:conversation_id/mute
  def unmute(conn, %{"conversation_id" => conversation_id} = params) do
    case resolve_user_id(conn, params) do
      {:ok, user_id} ->
        case Manager.set_muted(user_id, conversation_id, false) do
          {:ok, _} -> send_resp(conn, 204, "")
          {:error, changeset} -> unprocessable(conn, changeset)
        end

      {:error, :missing_user_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: %{user_id: ["is required"]}})
    end
  end

  defp resolve_user_id(conn, params) do
    case params["user_id"] || conn.assigns[:jwt_sub] do
      nil -> {:error, :missing_user_id}
      "" -> {:error, :missing_user_id}
      uid when is_binary(uid) -> {:ok, uid}
    end
  end

  defp build_opts(params) do
    case parse_until(params["mute_until"]) do
      :none -> {:ok, []}
      {:ok, dt} -> {:ok, [mute_until: dt]}
      {:error, _} = err -> err
    end
  end

  defp parse_until(nil), do: :none
  defp parse_until(""), do: :none

  defp parse_until(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, DateTime.truncate(dt, :second)}
      {:error, _reason} -> {:error, :invalid_datetime}
    end
  end

  defp parse_until(_), do: {:error, :invalid_datetime}

  defp unprocessable(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {k, v}, acc ->
          String.replace(acc, "%{#{k}}", to_string(v))
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end
end
