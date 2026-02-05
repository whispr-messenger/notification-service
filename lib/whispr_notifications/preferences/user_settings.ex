defmodule WhisprNotifications.Preferences.UserSettings do
  @moduledoc """
  Réglages de notifications au niveau utilisateur (globaux).
  """

  @enforce_keys [:user_id]
  defstruct [
    :user_id,
    :language,
    :timezone,
    # Types de notifications
    message_push_enabled: true,
    message_email_enabled: false,
    system_push_enabled: true,
    marketing_push_enabled: false,
    # Horaires silencieux (mute global)
    quiet_hours_start: nil,
    quiet_hours_end: nil
  ]

  @type t :: %__MODULE__{
          user_id: String.t(),
          language: String.t() | nil,
          timezone: String.t() | nil,
          message_push_enabled: boolean(),
          message_email_enabled: boolean(),
          system_push_enabled: boolean(),
          marketing_push_enabled: boolean(),
          quiet_hours_start: Time.t() | nil,
          quiet_hours_end: Time.t() | nil
        }

  @spec quiet_now?(t(), DateTime.t()) :: boolean()
  def quiet_now?(%__MODULE__{quiet_hours_start: nil, quiet_hours_end: nil}, _now), do: false

  def quiet_now?(%__MODULE__{} = settings, now) do
    # on se contente de comparer les heures dans le timezone de l’utilisateur si fourni
    time =
      case settings.timezone do
        nil -> DateTime.to_time(now)
        tz  -> now |> DateTime.shift_zone!(tz) |> DateTime.to_time()
      end

    qs = settings.quiet_hours_start
    qe = settings.quiet_hours_end

    cond do
      is_nil(qs) or is_nil(qe) ->
        false

      Time.compare(qs, qe) == :lt ->
        # fenêtre dans la même journée
        Time.compare(time, qs) != :lt and Time.compare(time, qe) != :gt

      true ->
        # fenêtre qui passe minuit (ex: 22h-07h)
        Time.compare(time, qs) != :lt or Time.compare(time, qe) != :gt
    end
  end
end
