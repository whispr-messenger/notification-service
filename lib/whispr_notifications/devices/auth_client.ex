defmodule WhisprNotifications.Devices.AuthClient do
  @moduledoc """
  Adaptateur historique : la première version tirait les devices depuis
  auth-service par gRPC. Depuis WHISPR-1159 on les stocke localement
  dans la table `devices` (alimentée par l'endpoint POST /devices de
  WHISPR-1155), donc cette façade lit directement en base via le
  contexte `Devices`.

  Le nom est conservé pour éviter de casser les appelants
  (CacheManager, MessagingSubscriber).
  """

  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.DeviceCache

  @callback fetch_devices(String.t()) ::
              {:ok, DeviceCache.t()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def fetch_devices(user_id) when is_binary(user_id) and user_id != "" do
    devices =
      user_id
      |> Devices.list_active_for_user()
      |> Enum.map(&to_cache_device/1)

    {:ok, %DeviceCache{user_id: user_id, devices: devices}}
  rescue
    # En test async la connexion Ecto n'est pas partagée avec le
    # GenServer CacheManager qui appelle cette fonction. Plutôt que
    # de faire planter les tests qui n'ont rien à voir avec les
    # devices, on renvoie {:error, ...} — deliver_if_possible saura
    # skipper la livraison.
    e in DBConnection.OwnershipError ->
      {:error, {:db_unavailable, e}}

    e ->
      {:error, {:db_error, e}}
  end

  def fetch_devices(_), do: {:error, :invalid_user_id}

  defp to_cache_device(device) do
    %{
      token: device.fcm_token,
      platform: platform_atom(device.platform),
      app: device.app_version,
      device_id: device.device_id,
      internal_id: device.id
    }
  end

  defp platform_atom("android"), do: :android
  defp platform_atom("ios"), do: :ios
  defp platform_atom("web"), do: :web
  defp platform_atom(_), do: :android
end
