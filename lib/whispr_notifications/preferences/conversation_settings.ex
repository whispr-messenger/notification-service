defmodule WhisprNotifications.Preferences.ConversationSettings do
  @moduledoc """
  Réglages de notifications au niveau conversation.
  On gère surtout le mute, la priorité, etc.
  """

  @enforce_keys [:user_id, :conversation_id]
  defstruct [
    :user_id,
    :conversation_id,
    muted: false,
    mute_until: nil,
    # priorité locale: :normal | :high | :low
    priority: :normal
  ]

  @type priority :: :high | :normal | :low

  @type t :: %__MODULE__{
          user_id: String.t(),
          conversation_id: String.t(),
          muted: boolean(),
          mute_until: DateTime.t() | nil,
          priority: priority()
        }

  @spec muted_now?(t(), DateTime.t()) :: boolean()
  def muted_now?(%__MODULE__{muted: true, mute_until: nil}, _now), do: true

  def muted_now?(%__MODULE__{muted: true, mute_until: until}, now)
      when not is_nil(until),
      do: DateTime.compare(until, now) == :gt

  def muted_now?(_settings, _now), do: false
end
