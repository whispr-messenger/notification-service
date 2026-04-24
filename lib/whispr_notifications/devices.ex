defmodule WhisprNotifications.Devices do
  @moduledoc """
  Contexte Devices — CRUD sur la table `devices`.

  Utilisé par :

    * `AuthClient.fetch_devices/1` pour lister les devices actifs d'un
      user (fan-out push).
    * `BatchProcessor` pour marquer un token `:token_invalid` (retour
      `UNREGISTERED` / `INVALID_ARGUMENT` etc. de FCM) en soft-delete.
    * `TokenRefresher` pour purger les tokens invalides anciens.

  Jamais de suppression dure côté chemin chaud : on passe toujours par
  `soft_delete/1`.
  """

  import Ecto.Query, warn: false

  alias WhisprNotifications.Devices.Device
  alias WhisprNotifications.Repo

  @type platform :: :android | :ios | :web

  @spec list_active_for_user(binary()) :: [Device.t()]
  def list_active_for_user(user_id) when is_binary(user_id) do
    from(d in Device, where: d.user_id == ^user_id and is_nil(d.deleted_at))
    |> Repo.all()
  end

  @spec upsert(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def upsert(attrs) do
    changeset = Device.changeset(%Device{}, attrs)

    case Repo.insert(changeset,
           on_conflict: {:replace, [:fcm_token, :platform, :app_version, :updated_at]},
           conflict_target:
             {:unsafe_fragment, ~s|("user_id", "device_id") WHERE deleted_at IS NULL|},
           returning: true
         ) do
      {:ok, device} -> {:ok, device}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Soft-delete un device par id interne (uuid).
  """
  @spec soft_delete(binary()) :: {:ok, Device.t()} | {:error, :not_found}
  def soft_delete(id) when is_binary(id) do
    case Repo.get(Device, id) do
      nil ->
        {:error, :not_found}

      device ->
        device
        |> Ecto.Changeset.change(deleted_at: now())
        |> Repo.update()
    end
  end

  @doc """
  Soft-delete un device par couple (user_id, device_id) — endpoint
  DELETE /devices/:device_id. Idempotent : si déjà supprimé / absent,
  renvoie :ok sans erreur.
  """
  @spec soft_delete_by_user_device(binary(), binary()) :: :ok
  def soft_delete_by_user_device(user_id, device_id)
      when is_binary(user_id) and is_binary(device_id) do
    from(d in Device,
      where: d.user_id == ^user_id and d.device_id == ^device_id and is_nil(d.deleted_at)
    )
    |> Repo.update_all(set: [deleted_at: now(), updated_at: now()])

    :ok
  end

  @doc """
  Marque un token comme invalide (retour `:token_invalid` de FcmClient).
  On persiste le code d'erreur et on soft-delete dans la foulée, pour
  ne plus viser ce token au prochain fan-out.
  """
  @spec mark_invalid(binary(), String.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def mark_invalid(fcm_token, reason \\ "INVALID")
      when is_binary(fcm_token) and is_binary(reason) do
    now = now()

    {count, _} =
      from(d in Device,
        where: d.fcm_token == ^fcm_token and is_nil(d.deleted_at)
      )
      |> Repo.update_all(
        set: [last_error: reason, last_error_at: now, deleted_at: now, updated_at: now]
      )

    case count do
      0 -> {:error, :not_found}
      _ -> :ok
    end
  end

  @doc """
  Devices avec `last_error` et dont l'invalidation date d'avant
  `cutoff`. Utilisé par TokenRefresher pour la purge > 30 jours.
  """
  @spec list_invalidated_before(DateTime.t()) :: [Device.t()]
  def list_invalidated_before(%DateTime{} = cutoff) do
    from(d in Device,
      where:
        not is_nil(d.last_error) and not is_nil(d.last_error_at) and
          d.last_error_at < ^cutoff
    )
    |> Repo.all()
  end

  @doc """
  Métriques pour Prometheus : {active_count, invalid_count}.
  `active` = non-supprimés. `invalid` = supprimés via mark_invalid
  (deleted_at ET last_error présents).
  """
  @spec count_by_status() :: %{active: non_neg_integer(), invalid: non_neg_integer()}
  def count_by_status do
    active =
      from(d in Device, where: is_nil(d.deleted_at), select: count(d.id))
      |> Repo.one()

    invalid =
      from(d in Device,
        where: not is_nil(d.deleted_at) and not is_nil(d.last_error),
        select: count(d.id)
      )
      |> Repo.one()

    %{active: active || 0, invalid: invalid || 0}
  end

  @doc """
  Supprime définitivement un device déjà soft-deleted et invalide.
  Réservé à TokenRefresher après expiration de la fenêtre de rétention.
  """
  @spec hard_delete(binary()) :: {non_neg_integer(), nil}
  def hard_delete(id) when is_binary(id) do
    from(d in Device, where: d.id == ^id)
    |> Repo.delete_all()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
