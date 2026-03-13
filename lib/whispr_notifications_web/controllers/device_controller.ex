defmodule WhisprNotificationsWeb.DeviceController do
  use WhisprNotificationsWeb, :controller

  alias WhisprNotifications.Devices

  @doc """
  POST /api/v1/devices
  Registers or updates a device token for push notifications.

  Expected body:
    {
      "token": "fcm_or_apns_token",
      "platform": "ios" | "android",
      "device_id": "unique_device_identifier"
    }

  The user_id is expected to come from the authenticated session
  (extracted from the authorization header by upstream middleware).
  """
  def create(conn, params) do
    user_id = get_user_id(conn, params)

    attrs = %{
      user_id: user_id,
      token: params["token"],
      platform: params["platform"],
      device_id: params["device_id"]
    }

    case Devices.register_device(attrs) do
      {:ok, device} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: device.id,
          user_id: device.user_id,
          token: device.token,
          platform: device.platform,
          device_id: device.device_id,
          active: device.active,
          inserted_at: device.inserted_at
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/devices/:device_id
  Removes a device registration.
  """
  def delete(conn, %{"device_id" => device_id} = params) do
    user_id = get_user_id(conn, params)

    case Devices.remove_device(user_id, device_id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Device not found"})
    end
  end

  @doc """
  GET /api/v1/devices
  Lists all active devices for the current user.
  """
  def index(conn, params) do
    user_id = get_user_id(conn, params)
    devices = Devices.list_user_devices(user_id)

    json(conn, %{
      devices: Enum.map(devices, fn d ->
        %{
          id: d.id,
          token: d.token,
          platform: d.platform,
          device_id: d.device_id,
          active: d.active,
          inserted_at: d.inserted_at
        }
      end)
    })
  end

  defp get_user_id(conn, params) do
    # In production, user_id would come from JWT/auth middleware.
    # Fall back to params for now.
    Map.get(params, "user_id") || get_req_header(conn, "x-user-id") |> List.first()
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp format_errors(error), do: %{detail: inspect(error)}
end
