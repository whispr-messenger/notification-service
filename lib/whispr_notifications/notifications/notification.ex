defmodule WhisprNotifications.Notifications.Notification do
  @moduledoc """
  Représente une notification interne dans le système.
  Sert de DTO pour la livraison et de schéma Ecto pour l'historique.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # Column is `uuid` in the DB (see create_notification_history migration),
  # so use Ecto.UUID to serialise the text-form UUID into the expected 16-byte
  # binary. Declaring :string caused DBConnection.EncodeError on insert.
  @primary_key {:id, Ecto.UUID, autogenerate: false}

  @types ~w(message group system)a
  @required_new_keys [:user_id, :type, :title, :body]

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

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notif \\ %__MODULE__{}, attrs) do
    notif
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
  end

  @spec new(map()) :: t()
  def new(attrs) do
    :ok = validate_required!(attrs)

    id = Map.get(attrs, :id) || Ecto.UUID.generate()
    created_at = Map.get(attrs, :created_at) || now()

    struct!(__MODULE__, Map.merge(%{id: id, created_at: created_at}, attrs))
  end

  defp validate_required!(attrs) do
    missing =
      Enum.filter(@required_new_keys, fn key ->
        is_nil(Map.get(attrs, key))
      end)

    case missing do
      [] ->
        :ok

      keys ->
        raise ArgumentError, "missing required keys for Notification.new/1: #{inspect(keys)}"
    end
  end

  @spec mark_read(t(), DateTime.t()) :: t()
  def mark_read(%__MODULE__{} = notif, at \\ now()) do
    %__MODULE__{notif | read_at: DateTime.truncate(at, :second)}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
