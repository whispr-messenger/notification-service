defmodule WhisprNotifications.Inbox.Item do
  @moduledoc """
  Schema Ecto pour un item de la boite de reception de notifications.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  @valid_event_types ~w(mention reply contact_request missed_call)

  schema "notification_inbox" do
    field :user_id, :string
    field :event_type, :string
    field :payload, :map
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @type t :: %__MODULE__{}

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:user_id, :event_type, :payload, :read_at])
    |> validate_required([:user_id, :event_type, :payload])
    |> validate_inclusion(:event_type, @valid_event_types)
  end

  def valid_event_types, do: @valid_event_types
end
