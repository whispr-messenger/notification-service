defmodule WhisprNotifications.Devices.AuthClient do
  @moduledoc """
  Client gRPC (ou HTTP) vers le service d'auth pour récupérer les devices.
  Ce module est un port d’infrastructure.
  """

  alias WhisprNotifications.Devices.DeviceCache

  @callback fetch_devices(String.t()) ::
              {:ok, DeviceCache.t()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def fetch_devices(user_id) do
    # À adapter avec ton client gRPC réel.
    # Ici on renvoie un cache vide par défaut.
    {:ok, %DeviceCache{user_id: user_id, devices: []}}
  end
end
