defmodule WhisprNotificationsWeb.InboxController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Inbox

  @default_limit 20
  @max_limit 50

  @doc """
  GET /api/v1/inbox?cursor=<uuid>&limit=<int>

  Liste les items inbox de l'utilisateur authentifie, ordre antichronologique,
  pagination par curseur opaque (uuid de l'item).

  Params:
    - cursor (string, optionnel) — uuid du dernier item recus; retourne les items apres
    - limit  (integer, optionnel) — 1..50, defaut 20
  """
  def index(conn, params) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        opts = build_list_opts(params)
        items = Inbox.list(user_id, opts)
        unread = Inbox.count_unread(user_id)

        json(conn, %{
          items: Enum.map(items, &serialize_item/1),
          unread_count: unread
        })

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  @doc """
  POST /api/v1/inbox/mark-read

  Corps JSON (mutuellement exclusifs) :
    - { "ids": ["uuid", ...] } — marque les items specifies comme lus
    - { "all": true }          — marque tous les items de l'utilisateur comme lus

  Retourne le nombre d'items mis a jour.
  """
  def mark_read(conn, params) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        do_mark_read(conn, user_id, params)

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  # --- helpers prive ---

  defp do_mark_read(conn, _user_id, %{"all" => true, "ids" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "params 'all' et 'ids' sont mutuellement exclusifs"})
  end

  defp do_mark_read(conn, user_id, %{"all" => true}) do
    {:ok, count} = Inbox.mark_read(user_id, :all)
    json(conn, %{updated: count})
  end

  defp do_mark_read(conn, user_id, %{"ids" => ids}) when is_list(ids) do
    case validate_ids(ids) do
      {:ok, valid_ids} ->
        {:ok, count} = Inbox.mark_read(user_id, valid_ids)
        json(conn, %{updated: count})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: reason})
    end
  end

  defp do_mark_read(conn, _user_id, %{"ids" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "'ids' doit etre une liste de strings"})
  end

  defp do_mark_read(conn, _user_id, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "corps invalide: 'ids' (liste) ou 'all' (true) requis"})
  end

  defp validate_ids(ids) do
    valid =
      Enum.filter(ids, fn
        id when is_binary(id) and id != "" -> true
        _ -> false
      end)

    case valid do
      [] -> {:error, "liste 'ids' vide ou invalide"}
      _ -> {:ok, valid}
    end
  end

  defp build_list_opts(params) do
    cursor = params["cursor"]
    limit = parse_limit(params["limit"])

    opts = [limit: limit]
    if is_binary(cursor) and cursor != "", do: [{:cursor, cursor} | opts], else: opts
  end

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> clamp(n)
      _ -> @default_limit
    end
  end

  defp parse_limit(n) when is_integer(n), do: clamp(n)
  defp parse_limit(_), do: @default_limit

  defp clamp(n) when n < 1, do: 1
  defp clamp(n) when n > @max_limit, do: @max_limit
  defp clamp(n), do: n

  defp serialize_item(item) do
    %{
      id: item.id,
      user_id: item.user_id,
      event_type: item.event_type,
      payload: item.payload,
      read_at: format_dt(item.read_at),
      created_at: format_dt(item.created_at)
    }
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(nil), do: nil
end
