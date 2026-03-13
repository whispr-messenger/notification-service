defmodule WhisprNotifications.Devices do
  @moduledoc """
  Context module for managing device token registrations.
  Handles CRUD operations for push notification device tokens.
  """

  import Ecto.Query
  alias WhisprNotifications.Repo
  alias WhisprNotifications.Devices.Device

  @doc """
  Registers a device token for a user.
  If the same user_id + device_id combination exists, the token is updated.
  If the same token exists on a different device, the old record is replaced.
  """
  def register_device(attrs) do
    user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")
    device_id = Map.get(attrs, :device_id) || Map.get(attrs, "device_id")

    case get_device_by_user_and_device(user_id, device_id) do
      nil ->
        %Device{}
        |> Device.changeset(normalize_attrs(attrs))
        |> Repo.insert()

      existing ->
        existing
        |> Device.changeset(normalize_attrs(attrs))
        |> Repo.update()
    end
  end

  @doc """
  Returns all active devices for a given user.
  """
  def list_user_devices(user_id) do
    Device
    |> where([d], d.user_id == ^user_id and d.active == true)
    |> Repo.all()
  end

  @doc """
  Deactivates a device by token (e.g., when FCM reports an invalid token).
  """
  def deactivate_device(token) do
    case Repo.get_by(Device, token: token) do
      nil -> {:error, :not_found}
      device ->
        device
        |> Device.changeset(%{active: false})
        |> Repo.update()
    end
  end

  @doc """
  Removes a specific device registration.
  """
  def remove_device(user_id, device_id) do
    case get_device_by_user_and_device(user_id, device_id) do
      nil -> {:error, :not_found}
      device -> Repo.delete(device)
    end
  end

  defp get_device_by_user_and_device(user_id, device_id) do
    Device
    |> where([d], d.user_id == ^user_id and d.device_id == ^device_id)
    |> Repo.one()
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end
end
