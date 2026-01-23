defmodule WhisprNotifications.Devices.DeviceCache do
  @moduledoc """
  Représentation du cache de devices d’un utilisateur.
  """

  @enforce_keys [:user_id]
  defstruct [
    :user_id,
    # liste de devices connus pour cet utilisateur
    devices: []
  ]

  @type platform :: :ios | :android | :web

  @type device :: %{
          token: String.t(),
          platform: platform(),
          # optionnel: app bundle, env, etc.
          app: String.t() | nil
        }

  @type t :: %__MODULE__{
          user_id: String.t(),
          devices: [device()]
        }

  @spec add_device(t(), device()) :: t()
  def add_device(%__MODULE__{devices: devices} = cache, device) do
    # on déduplique par token
    new_devices =
      devices
      |> Enum.reject(&(&1.token == device.token))
      |> Kernel.++([device])

    %__MODULE__{cache | devices: new_devices}
  end

  @spec remove_device(t(), String.t()) :: t()
  def remove_device(%__MODULE__{devices: devices} = cache, token) do
    %__MODULE__{cache | devices: Enum.reject(devices, &(&1.token == token))}
  end
end
