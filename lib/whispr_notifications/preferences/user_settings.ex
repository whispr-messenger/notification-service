defmodule WhisprNotifications.Preferences.UserSettings do
  @moduledoc """
  Réglages de notifications au niveau utilisateur (globaux).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_settings" do
    field :user_id, :string
    field :language, :string
    field :timezone, :string
    field :message_push_enabled, :boolean, default: true
    field :message_email_enabled, :boolean, default: false
    field :system_push_enabled, :boolean, default: true
    field :marketing_push_enabled, :boolean, default: false
    field :mentions_only, :boolean, default: false
    field :quiet_hours_start, :time
    field :quiet_hours_end, :time

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          language: String.t() | nil,
          timezone: String.t() | nil,
          message_push_enabled: boolean(),
          message_email_enabled: boolean(),
          system_push_enabled: boolean(),
          marketing_push_enabled: boolean(),
          mentions_only: boolean(),
          quiet_hours_start: Time.t() | nil,
          quiet_hours_end: Time.t() | nil
        }

  @cast_fields [
    :user_id,
    :language,
    :timezone,
    :message_push_enabled,
    :message_email_enabled,
    :system_push_enabled,
    :marketing_push_enabled,
    :mentions_only,
    :quiet_hours_start,
    :quiet_hours_end
  ]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @cast_fields)
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  @spec quiet_now?(t(), DateTime.t()) :: boolean()
  def quiet_now?(%__MODULE__{quiet_hours_start: nil, quiet_hours_end: nil}, _now), do: false

  def quiet_now?(%__MODULE__{} = settings, now) do
    time =
      case settings.timezone do
        nil -> DateTime.to_time(now)
        tz -> now |> DateTime.shift_zone!(tz) |> DateTime.to_time()
      end

    qs = settings.quiet_hours_start
    qe = settings.quiet_hours_end

    cond do
      is_nil(qs) or is_nil(qe) ->
        false

      Time.compare(qs, qe) == :lt ->
        Time.compare(time, qs) != :lt and Time.compare(time, qe) != :gt

      true ->
        Time.compare(time, qs) != :lt or Time.compare(time, qe) != :gt
    end
  end
end
