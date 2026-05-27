defmodule WhisprNotifications.Devices.Device do
  @moduledoc """
  Schéma Ecto d'un device utilisateur (token FCM / APNS / Web Push endpoint).

  Géré par `WhisprNotifications.Devices`. Le soft-delete se fait en
  mettant `deleted_at` — les lignes ne sont jamais effacées pour
  conserver la trace d'une invalidation.

  Pour la plateforme `web_push`, `fcm_token` stocke l'endpoint VAPID,
  `wp_p256dh` et `wp_auth` stockent les clés de chiffrement du device.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  # "web" conservé pour rétrocompatibilité ; "web_push" est la valeur active
  @platforms ~w(android ios web web_push)
  @required ~w(user_id device_id fcm_token platform)a
  @web_push_required ~w(wp_p256dh wp_auth)a

  schema "devices" do
    field :user_id, :string
    field :device_id, :string
    field :fcm_token, :string
    field :platform, :string
    field :app_version, :string
    field :wp_p256dh, :string
    field :wp_auth, :string
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
      :wp_p256dh,
      :wp_auth,
      :last_error,
      :last_error_at,
      :deleted_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:platform, @platforms)
    |> validate_length(:fcm_token, min: 1)
    |> validate_web_push_keys()
  end

  def platforms, do: @platforms

  # wp_p256dh et wp_auth sont obligatoires quand platform = "web_push"
  defp validate_web_push_keys(changeset) do
    case get_field(changeset, :platform) do
      "web_push" -> validate_required(changeset, @web_push_required)
      _ -> changeset
    end
  end
end
