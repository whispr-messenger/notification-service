defmodule WhisprNotifications.Badges.BadgeCount do
  @moduledoc """
  Ecto schema pour le compteur de notifications non lues par utilisateur.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :string, autogenerate: false}

  schema "user_badge_counts" do
    field :unread_count, :integer, default: 0
    field :updated_at, :utc_datetime
  end

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          unread_count: integer(),
          updated_at: DateTime.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(badge \\ %__MODULE__{}, attrs) do
    badge
    |> cast(attrs, [:user_id, :unread_count, :updated_at])
    |> validate_required([:user_id, :unread_count, :updated_at])
    |> validate_number(:unread_count, greater_than_or_equal_to: 0)
  end
end
