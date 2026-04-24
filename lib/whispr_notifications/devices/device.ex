defmodule WhisprNotifications.Devices.Device do
  @moduledoc """
  Schéma Ecto d'un device utilisateur (token FCM / APNS).

  Géré par `WhisprNotifications.Devices`. Le soft-delete se fait en
  mettant `deleted_at` — les lignes ne sont jamais effacées pour
  conserver la trace d'une invalidation FCM.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  @platforms ~w(android ios web)
  @required ~w(user_id device_id fcm_token platform)a

  schema "devices" do
    field :user_id, :string
    field :device_id, :string
    field :fcm_token, :string
    field :platform, :string
    field :app_version, :string
    field :last_error, :string
    field :last_error_at, :utc_datetime
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :user_id,
      :device_id,
      :fcm_token,
      :platform,
      :app_version,
      :last_error,
      :last_error_at,
      :deleted_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:platform, @platforms)
    |> validate_length(:fcm_token, min: 1)
  end

  def platforms, do: @platforms
end
