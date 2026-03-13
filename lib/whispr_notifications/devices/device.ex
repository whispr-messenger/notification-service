defmodule WhisprNotifications.Devices.Device do
  @moduledoc """
  Ecto schema for registered push notification devices.
  Each device is associated with a user and stores the FCM/APNS push token.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @platforms ~w(ios android)

  schema "devices" do
    field :user_id, :binary_id
    field :token, :string
    field :platform, :string
    field :device_id, :string
    field :active, :boolean, default: true

    timestamps()
  end

  @doc """
  Changeset for registering a new device or updating an existing one.
  """
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:user_id, :token, :platform, :device_id, :active])
    |> validate_required([:user_id, :token, :platform, :device_id])
    |> validate_inclusion(:platform, @platforms)
    |> unique_constraint(:token, name: :devices_token_unique_index)
    |> unique_constraint([:user_id, :device_id], name: :devices_user_device_unique_index)
  end
end
