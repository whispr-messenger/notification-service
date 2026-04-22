defmodule WhisprNotifications.Notifications.Formatter do
  @moduledoc """
  Formattage spécifique par plateforme (FCM, APNS, etc.).
  Transforme un `Notification` en payload prêt à envoyer.
  """

  alias WhisprNotifications.Notifications.Notification

  @type platform :: :ios | :android | :web

  @spec to_platform_payload(Notification.t(), platform()) :: map()
  def to_platform_payload(notif, platform), do: to_platform_payload(notif, platform, nil)

  @spec to_platform_payload(Notification.t(), platform(), non_neg_integer() | nil) :: map()
  def to_platform_payload(%Notification{} = n, :android, badge) do
    notification =
      %{title: n.title, body: n.body}
      |> maybe_put_badge(badge)

    %{
      notification: notification,
      data:
        n.context
        |> Map.merge(%{
          "notification_id" => n.id,
          "type" => Atom.to_string(n.type)
        })
        |> maybe_put_data_badge(badge)
    }
  end

  def to_platform_payload(%Notification{} = n, :ios, badge) do
    aps =
      %{
        "alert" => %{
          "title" => n.title,
          "body" => n.body
        },
        "sound" => "default"
      }
      |> maybe_put_badge(badge)

    %{
      "aps" => aps,
      "meta" => %{
        "notification_id" => n.id,
        "type" => Atom.to_string(n.type)
      }
    }
  end

  def to_platform_payload(%Notification{} = n, :web, _badge) do
    %{
      "title" => n.title,
      "body" => n.body,
      "data" => Map.put(n.context, "notification_id", n.id)
    }
  end

  defp maybe_put_badge(map, nil), do: map

  defp maybe_put_badge(map, badge) when is_integer(badge) and badge >= 0 do
    Map.put(map, key_for(map, "badge"), badge)
  end

  defp maybe_put_data_badge(data, nil), do: data

  defp maybe_put_data_badge(data, badge) when is_integer(badge) and badge >= 0 do
    Map.put(data, "badge", Integer.to_string(badge))
  end

  defp key_for(map, key) do
    cond do
      Map.has_key?(map, key) -> key
      Enum.any?(Map.keys(map), &is_atom/1) -> String.to_atom(key)
      true -> key
    end
  end
end
