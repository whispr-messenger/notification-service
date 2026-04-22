defmodule WhisprNotifications.Notifications.History do
  @moduledoc """
  Gestion de l'historique des notifications (persistance, requêtes).
  Persiste les notifications dans `notification_history` via Ecto.
  """

  import Ecto.Query

  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotifications.Repo

  require Logger

  defmodule Behaviour do
    @moduledoc "Behaviour pour la persistance de l'historique des notifications."

    @callback save(WhisprNotifications.Notifications.Notification.t()) :: :ok | {:error, term()}
    @callback mark_read(String.t(), DateTime.t()) :: :ok
    @callback list_for_user(String.t(), keyword()) ::
                [WhisprNotifications.Notifications.Notification.t()]
  end

  @behaviour Behaviour

  @impl true
  @spec save(Notification.t()) :: :ok | {:error, Ecto.Changeset.t() | term()}
  def save(%Notification{} = notif) do
    attrs = notif |> Map.from_struct() |> Map.drop([:__meta__])

    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :id)
    |> case do
      {:ok, _record} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "[Notifications.History] failed to persist notification #{notif.id}: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  @impl true
  @spec mark_read(String.t(), DateTime.t()) :: :ok
  def mark_read(id, at \\ DateTime.utc_now()) do
    at = DateTime.truncate(at, :second)

    {_count, _} =
      from(n in Notification, where: n.id == ^id)
      |> Repo.update_all(set: [read_at: at])

    :ok
  end

  @impl true
  @spec list_for_user(String.t(), keyword()) :: [Notification.t()]
  def list_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(n in Notification,
      where: n.user_id == ^user_id,
      order_by: [desc: n.created_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end
end
