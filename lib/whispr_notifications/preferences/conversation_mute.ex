defmodule WhisprNotifications.Preferences.ConversationMute do
  @moduledoc """
  Ecto schema for per-conversation mute settings.
  Allows users to mute notifications for specific conversations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversation_mutes" do
    field :user_id, :binary_id
    field :conversation_id, :binary_id
    field :muted_until, :utc_datetime

    timestamps()
  end

  def changeset(mute, attrs) do
    mute
    |> cast(attrs, [:user_id, :conversation_id, :muted_until])
    |> validate_required([:user_id, :conversation_id])
    |> unique_constraint([:user_id, :conversation_id],
      name: :conversation_mutes_user_conversation_unique_index
    )
  end
end
