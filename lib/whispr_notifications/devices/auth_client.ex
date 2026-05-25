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

    # coveralls-ignore-next-line — defensive Ecto fallback for non-ownership Repo failures
    e ->
      {:error, {:db_error, e}}

      # coveralls-ignore-start
  catch
    :exit, reason ->
      {:error, {:db_unavailable, reason}}
      # coveralls-ignore-stop
  end

  def fetch_devices(_), do: {:error, :invalid_user_id}

  defp to_cache_device(device) do
    base = %{
      token: device.fcm_token,
      platform: platform_atom(device.platform),
      app: app_topic(device),
      device_id: device.device_id,
      internal_id: device.id
    }

    # pour web_push, on transporte les clés VAPID dans le cache
    case device.platform do
      "web_push" ->
        Map.merge(base, %{
          wp_p256dh: device.wp_p256dh,
          wp_auth: device.wp_auth
        })

      _ ->
        base
    end
  end

  defp app_topic(%{platform: "ios"}) do
    :whispr_notification
    |> Application.get_env(:apns, [])
    |> Keyword.get(:default_topic)
  end

  defp app_topic(device), do: device.app_version

  defp platform_atom("android"), do: :android
  defp platform_atom("ios"), do: :ios
  defp platform_atom("web"), do: :web
  defp platform_atom("web_push"), do: :web_push
  defp platform_atom(_), do: :android
end
