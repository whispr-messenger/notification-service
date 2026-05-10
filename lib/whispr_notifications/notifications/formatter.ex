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
      # collapse_key : FCM deduplique cote delivery quand on rejoue le meme
      # event (subscriber Redis qui re-publie apres un :DOWN par exemple).
      # on derive de l'id de notif pour avoir une cle stable par message.
      collapse_key: collapse_key_for(n),
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
      # meme principe que collapse_key cote FCM : APNs collapse_id deduplique
      # un push si on rejoue le meme event apres une race :DOWN.
      "collapse_id" => collapse_key_for(n),
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

  # cle de dedup stable par notification. APNs limite collapse_id a 64 octets
  # et FCM ne fixe pas de borne, donc le prefixe + UUID rentre toujours.
  defp collapse_key_for(%Notification{id: id}) when is_binary(id) and id != "",
    do: "msg:" <> id

  # coveralls-ignore-next-line - defensive : id est require par Notification.new/1
  defp collapse_key_for(_), do: nil
end
