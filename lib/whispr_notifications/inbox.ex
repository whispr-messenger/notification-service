defmodule WhisprNotifications.Inbox do
  @moduledoc """
  Contexte Inbox — gestion des notifications en boite de reception utilisateur.
  """

  import Ecto.Query, warn: false

  alias WhisprNotifications.Inbox.Item
  alias WhisprNotifications.Repo

  @default_limit 20
  @max_limit 50

  @doc """
  Liste les items inbox d'un utilisateur, ordre created_at desc, pagination par curseur.

  opts:
    - cursor: uuid string | nil  (exclusif, commence apres cet id)
    - limit: integer 1..50, default 20
  """
  @spec list(binary(), keyword()) :: [Item.t()]
  def list(user_id, opts \\ []) when is_binary(user_id) do
    limit = clamp_limit(Keyword.get(opts, :limit, @default_limit))
    cursor_id = Keyword.get(opts, :cursor)

    query =
      from(i in Item,
        where: i.user_id == ^user_id,
        order_by: [desc: i.created_at, desc: i.id],
        limit: ^limit
      )

    query =
      if cursor_id do
        # cursor-based: on recupere le created_at du curseur pour continuer apres
        case Repo.get(Item, cursor_id) do
          nil ->
            query

          %Item{created_at: cursor_ts} ->
            from(i in query,
              where:
                i.created_at < ^cursor_ts or
                  (i.created_at == ^cursor_ts and i.id < ^cursor_id)
            )
        end
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Compte les items non lus (read_at IS NULL) pour un utilisateur.
  """
  @spec count_unread(binary()) :: non_neg_integer()
  def count_unread(user_id) when is_binary(user_id) do
    from(i in Item,
      where: i.user_id == ^user_id and is_nil(i.read_at),
      select: count(i.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Marque les items comme lus.

  - `mark_read(user_id, ids)` ou `mark_read(user_id, :all)`
  - Filter strict par user_id pour eviter cross-user IDOR.
  - Retourne {:ok, count} items mis a jour.
  """
  @spec mark_read(binary(), [binary()] | :all) :: {:ok, non_neg_integer()}
  def mark_read(user_id, :all) when is_binary(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(i in Item,
        where: i.user_id == ^user_id and is_nil(i.read_at)
      )
      |> Repo.update_all(set: [read_at: now])

    {:ok, count}
  end

  def mark_read(user_id, ids)
      when is_binary(user_id) and is_list(ids) and length(ids) > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(i in Item,
        where: i.user_id == ^user_id and i.id in ^ids and is_nil(i.read_at)
      )
      |> Repo.update_all(set: [read_at: now])

    {:ok, count}
  end

  def mark_read(_user_id, []), do: {:ok, 0}

  @doc """
  Insere un item dans l'inbox et retourne {:ok, Item.t()}.
  """
  @spec insert(binary(), binary(), map()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def insert(user_id, event_type, payload)
      when is_binary(user_id) and is_binary(event_type) and is_map(payload) do
    %Item{}
    |> Item.changeset(%{user_id: user_id, event_type: event_type, payload: payload})
    |> Repo.insert()
  end

  # borne le limit entre 1 et @max_limit
  defp clamp_limit(n) when is_integer(n) and n >= 1 and n <= @max_limit, do: n
  defp clamp_limit(n) when is_integer(n) and n < 1, do: 1
  defp clamp_limit(n) when is_integer(n) and n > @max_limit, do: @max_limit
  defp clamp_limit(_), do: @default_limit
end
