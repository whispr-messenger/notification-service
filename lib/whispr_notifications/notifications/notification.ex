defmodule WhisprNotifications.Notifications.Notification do
  @moduledoc """
  Représente une notification interne dans le système.
  Sert de DTO pour la livraison et de schéma Ecto pour l'historique.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @types ~w(message group system)a

  schema "notification_history" do
    field :user_id, :string
    field :conversation_id, :string
    field :type, Ecto.Enum, values: @types
    field :title, :string
    field :body, :string
    field :context, :map, default: %{}
    field :metadata, :map, default: %{}
    field :created_at, :utc_datetime
    field :read_at, :utc_datetime
  end

  @type type :: :message | :group | :system

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          conversation_id: String.t() | nil,
          type: type() | nil,
          title: String.t() | nil,
          body: String.t() | nil,
          context: map(),
          created_at: DateTime.t() | nil,
          read_at: DateTime.t() | nil,
          metadata: map() | nil
        }

  @cast_fields [
    :id,
    :user_id,
    :conversation_id,
    :type,
    :title,
    :body,
    :context,
    :metadata,
    :created_at,
    :read_at
  ]

  @required_fields [:id, :user_id, :type, :title, :body, :created_at]
  @required_new_keys [:user_id, :type, :title, :body]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notif \\ %__MODULE__{}, attrs) do
    notif
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
  end

  @spec new(map()) :: t()
  def new(attrs) do
    missing = Enum.reject(@required_new_keys, &Map.has_key?(attrs, &1))

    unless missing == [] do
      raise ArgumentError,
            "missing required keys for Notification.new/1: #{inspect(missing)}"
    end

    id = Map.get(attrs, :id) || Ecto.UUID.generate()
    created_at = Map.get(attrs, :created_at) || now()

    struct!(__MODULE__, Map.merge(%{id: id, created_at: created_at}, attrs))
  end

  @spec mark_read(t(), DateTime.t()) :: t()
  def mark_read(%__MODULE__{} = notif, at \\ now()) do
    %__MODULE__{notif | read_at: DateTime.truncate(at, :second)}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
