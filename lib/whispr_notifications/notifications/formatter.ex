defmodule WhisprNotifications.Notifications.Formatter do
  @moduledoc """
  Formattage spécifique par plateforme (FCM, APNS, etc.).
  Transforme un `Notification` en payload prêt à envoyer.
  """

  alias WhisprNotifications.Notifications.Notification

  @type platform :: :ios | :android | :web

  @spec to_platform_payload(Notification.t(), platform()) :: map()
  def to_platform_payload(%Notification{} = n, :android) do
    %{
      notification: %{
        title: n.title,
        body: n.body
      },
      data: Map.merge(n.context, %{
        "notification_id" => n.id,
        "type" => Atom.to_string(n.type)
      })
    }
  end

  def to_platform_payload(%Notification{} = n, :ios) do
    %{
      "aps" => %{
        "alert" => %{
          "title" => n.title,
          "body" => n.body
        },
        "sound" => "default"
      },
      "meta" => %{
        "notification_id" => n.id,
        "type" => Atom.to_string(n.type)
      }
    }
  end

  def to_platform_payload(%Notification{} = n, :web) do
    %{
      "title" => n.title,
      "body" => n.body,
      "data" => Map.put(n.context, "notification_id", n.id)
    }
  end
end
