defmodule WhisprNotificationsWeb.DevicesController do
  use WhisprNotificationsWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias WhisprNotifications.Devices
  alias WhisprNotifications.Devices.Device
  alias WhisprNotifications.Repo

  @doc """
  POST /api/v1/devices

  Register or refresh a device for the authenticated user. The `user_id` is
  taken from the JWT `sub`; the body only carries client-side fields.

  Body (JSON):
  - `device_id` (string, required) — stable identifier chosen by the client
    (IDFV on iOS, Android ID / Instance ID on Android).
  - `fcm_token` (string, required) — current Firebase Cloud Messaging token.
  - `platform` (string, required) — `"android"` or `"ios"`.
  - `app_version` (string, optional) — mobile app version string.

  Responses:
  - `201 Created` on first registration of this `device_id` for the user.
  - `200 OK` when a row with the same `(user_id, device_id)` already existed
    (token rotation, app upgrade, reinstall, re-register after logout). This
    makes the endpoint idempotent — the client can POST on every app launch
    without special-casing.
  - `400 Bad Request` on validation errors.
  - `401 Unauthorized` if the JWT is missing or invalid.
  """
  def register(conn, params) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        do_register(conn, user_id, params)

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  @doc """
  DELETE /api/v1/devices/:device_id

  Unregister a device (soft-delete). Idempotent — returns 204 whether the
  device existed or not, so a client that retried or lost track of its
  registration state can always cleanly logout.
  """
  def unregister(conn, %{"device_id" => device_id}) do
    case conn.assigns[:jwt_sub] do
      user_id when is_binary(user_id) and user_id != "" ->
        :ok = Devices.soft_delete_by_user_device(user_id, device_id)
        send_resp(conn, 204, "")

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  defp do_register(conn, user_id, params) do
    device_id = params_get(params, "device_id")
    existed_before? = device_exists?(user_id, device_id)
    attrs = Map.put(ensure_string_keys(params), "user_id", user_id)

    case Devices.upsert(attrs) do
      {:ok, %Device{} = device} ->
        status = if existed_before?, do: :ok, else: :created
        conn |> put_status(status) |> json(serialize(device))

      {:error, %Changeset{} = changeset} ->
        conn |> put_status(:bad_request) |> json(%{errors: traverse_errors(changeset)})
    end
  end

  # Any prior row with this (user_id, device_id), including soft-deleted ones,
  # counts as "already registered" so re-registration after logout resolves to
  # 200 (not a surprise 201). The `Devices` context handles the actual
  # insert-vs-update decision via the partial unique index.
  defp device_exists?(_user_id, nil), do: false
  defp device_exists?(_user_id, ""), do: false

  defp device_exists?(user_id, device_id) when is_binary(device_id) do
    Repo.exists?(from d in Device, where: d.user_id == ^user_id and d.device_id == ^device_id)
  end

  defp device_exists?(_user_id, _), do: false

  defp params_get(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, String.to_atom(key))
  end

  defp params_get(_params, _key), do: nil

  defp ensure_string_keys(params) when is_map(params) do
    Map.new(params, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp ensure_string_keys(_), do: %{}

  defp serialize(%Device{} = d) do
    %{
      id: d.id,
      user_id: d.user_id,
      device_id: d.device_id,
      platform: d.platform,
      app_version: d.app_version,
      inserted_at: format_dt(d.inserted_at),
      updated_at: format_dt(d.updated_at)
    }
  end

  defp traverse_errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(_), do: nil
end
