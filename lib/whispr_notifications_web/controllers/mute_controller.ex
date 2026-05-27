defmodule WhisprNotificationsWeb.MuteController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Preferences.Manager

  # GET /api/conversations/mutes
  # Retourne la liste des conversations mutées par l'utilisateur courant (jwt_sub).
  # Permet au frontend de synchroniser l'etat is_muted au boot, vu que messaging-service
  # n'est pas la source de verite pour le mute (cf bug desync front<->back).
  def index(conn, _params) do
    case conn.assigns[:jwt_sub] do
      sub when is_binary(sub) ->
        mutes =
          sub
          |> Manager.list_muted_conversations()
          |> Enum.map(fn s ->
            %{
              conversation_id: s.conversation_id,
              muted: s.muted,
              mute_until: s.mute_until
            }
          end)

        json(conn, %{mutes: mutes})

      _ ->
        forbidden(conn)
    end
  end

  # POST /api/conversations/:conversation_id/mute
  # user_id: optionnel dans le body. S'il est fourni, il doit être égal au
  # `sub` du JWT, sinon 403. S'il est absent, le `sub` du JWT est utilisé.
  # Body/query params: mute_until (optionnel, ISO8601).
  def mute(conn, %{"conversation_id" => conversation_id} = params) do
    with {:ok, user_id} <- resolve_user_id(conn, params),
         {:ok, opts} <- build_opts(params) do
      case Manager.set_muted(user_id, conversation_id, true, opts) do
        {:ok, _} -> send_resp(conn, 204, "")
        {:error, changeset} -> unprocessable(conn, changeset)
      end
    else
      {:error, :forbidden} ->
        forbidden(conn)

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

      {:error, :forbidden} ->
        forbidden(conn)
    end
  end

  defp resolve_user_id(conn, params) do
    jwt_sub = conn.assigns[:jwt_sub]

    body_user_id =
      case params["user_id"] do
        "" -> nil
        value -> value
      end

    case {jwt_sub, body_user_id} do
      {sub, nil} when is_binary(sub) -> {:ok, sub}
      {sub, sub} when is_binary(sub) -> {:ok, sub}
      _ -> {:error, :forbidden}
    end
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "forbidden"})
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
