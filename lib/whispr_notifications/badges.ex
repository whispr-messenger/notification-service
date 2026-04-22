defmodule WhisprNotifications.Badges do
  @moduledoc """
  Contexte des compteurs de badge (notifications non lues par utilisateur).

  Expose des opérations idempotentes pour incrémenter, décrémenter, lire et
  réinitialiser le badge count utilisé pour l'icône de l'app (APNs `aps.badge`
  et FCM `notification.badge`).
  """

  import Ecto.Query

  alias WhisprNotifications.Badges.BadgeCount
  alias WhisprNotifications.Repo

  require Logger

  @doc """
  Récupère le compteur courant pour un utilisateur, 0 par défaut.
  """
  @spec get(String.t()) :: non_neg_integer()
  def get(user_id) when is_binary(user_id) do
    case Repo.get(BadgeCount, user_id) do
      nil -> 0
      %BadgeCount{unread_count: n} -> n
    end
  end

  @doc """
  Incrémente atomiquement le compteur d'un utilisateur et retourne la nouvelle valeur.
  """
  @spec incr(String.t(), pos_integer()) :: non_neg_integer()
  def incr(user_id, by \\ 1) when is_binary(user_id) and is_integer(by) and by > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.insert(
           %BadgeCount{user_id: user_id, unread_count: by, updated_at: now},
           on_conflict: [inc: [unread_count: by], set: [updated_at: now]],
           conflict_target: :user_id,
           returning: [:unread_count]
         ) do
      {:ok, %BadgeCount{unread_count: n}} ->
        n

      {:error, reason} ->
        Logger.warning("[Badges] incr failed for #{user_id}: #{inspect(reason)}")
        get(user_id)
    end
  end

  @doc """
  Décrémente le compteur en s'assurant qu'il reste >= 0.
  """
  @spec decr(String.t(), pos_integer()) :: non_neg_integer()
  def decr(user_id, by \\ 1) when is_binary(user_id) and is_integer(by) and by > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {_count, rows} =
      from(b in BadgeCount,
        where: b.user_id == ^user_id,
        update: [
          set: [
            unread_count: fragment("GREATEST(? - ?, 0)", b.unread_count, ^by),
            updated_at: ^now
          ]
        ],
        select: b.unread_count
      )
      |> Repo.update_all([])

    case rows do
      [n] -> n
      _ -> 0
    end
  end

  @doc """
  Force le compteur à une valeur donnée (utile pour reset à 0).
  """
  @spec set(String.t(), non_neg_integer()) :: non_neg_integer()
  def set(user_id, value)
      when is_binary(user_id) and is_integer(value) and value >= 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %BadgeCount{user_id: user_id, unread_count: value, updated_at: now},
      on_conflict: [set: [unread_count: value, updated_at: now]],
      conflict_target: :user_id
    )

    value
  end

  @doc """
  Remet le compteur à 0.
  """
  @spec reset(String.t()) :: 0
  def reset(user_id), do: set(user_id, 0)
end
