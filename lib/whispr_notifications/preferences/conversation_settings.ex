defmodule WhisprNotifications.Preferences.ConversationSettings do
  @moduledoc """
  Réglages de notifications au niveau conversation.
  On gère surtout le mute, la priorité, etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @priorities ~w(low normal high)a

  schema "conversation_settings" do
    field :user_id, :string
    field :conversation_id, :string
    field :muted, :boolean, default: false
    field :mute_until, :utc_datetime
    field :priority, Ecto.Enum, values: @priorities, default: :normal

    timestamps(type: :utc_datetime)
  end

  @type priority :: :high | :normal | :low

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          conversation_id: String.t() | nil,
          muted: boolean(),
          mute_until: DateTime.t() | nil,
          priority: priority()
        }

  @cast_fields [:user_id, :conversation_id, :muted, :mute_until, :priority]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @cast_fields)
    |> validate_required([:user_id, :conversation_id])
    |> unique_constraint([:user_id, :conversation_id],
      name: :conversation_settings_user_id_conversation_id_index
    )
  end

  @spec muted_now?(t(), DateTime.t()) :: boolean()
  def muted_now?(%__MODULE__{muted: true, mute_until: nil}, _now), do: true

  def muted_now?(%__MODULE__{muted: true, mute_until: until}, now)
      when not is_nil(until),
      do: DateTime.compare(until, now) == :gt

  def muted_now?(_settings, _now), do: false
end
