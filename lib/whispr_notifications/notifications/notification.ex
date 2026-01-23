defmodule WhisprNotifications.Notifications.Notification do
  @moduledoc """
  Représente une notification interne dans le système.
  """

  @enforce_keys [:id, :user_id, :type, :title, :body, :context]
  defstruct [
    :id,
    :user_id,
    :conversation_id,
    :type,
    :title,
    :body,
    :context,
    :created_at,
    :read_at,
    :metadata
  ]

  @type type :: :message | :group | :system

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          conversation_id: String.t() | nil,
          type: type(),
          title: String.t(),
          body: String.t(),
          context: map(),
          created_at: DateTime.t() | nil,
          read_at: DateTime.t() | nil,
          metadata: map() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) do
    id = Map.get(attrs, :id, Ecto.UUID.generate())
    created_at = Map.get(attrs, :created_at, DateTime.utc_now())

    struct!(__MODULE__, Map.merge(%{id: id, created_at: created_at}, attrs))
  end

  @spec mark_read(t(), DateTime.t()) :: t()
  def mark_read(%__MODULE__{} = notif, at \\ DateTime.utc_now()) do
    %__MODULE__{notif | read_at: at}
  end
end
