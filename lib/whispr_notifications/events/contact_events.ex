defmodule WhisprNotifications.Events.ContactEvents do
  @moduledoc """
  Notifications liées aux demandes de contact (envoi, acceptation).

  Le `requester_display_name` part en clair dans le payload FCM/APNS
  comme pour les autres types — Whispr ne chiffre pas le métadonnées
  d'enveloppe des notifications. Le `request_id` est inclus dans
  `context` pour qu'au tap le client mobile puisse deep-linker
  directement vers la fiche de la demande.
  """

  alias WhisprNotifications.Delivery.BatchProcessor
  alias WhisprNotifications.Devices.AuthClient
  alias WhisprNotifications.Notifications.{Filter, History, Notification}
  require Logger

  @type request_received :: %{
          required(:user_id) => String.t(),
          required(:requester_id) => String.t(),
          optional(:requester_display_name) => String.t(),
          optional(:request_id) => String.t()
        }

  @type request_accepted :: %{
          required(:user_id) => String.t(),
          required(:accepter_id) => String.t(),
          optional(:accepter_display_name) => String.t(),
          optional(:request_id) => String.t()
        }

  @spec handle_request_received(request_received()) :: :ok
  def handle_request_received(%{user_id: uid, requester_id: req_id} = event)
      when is_binary(uid) and uid != "" and is_binary(req_id) and req_id != "" do
    name = Map.get(event, :requester_display_name) || "Quelqu'un"

    notif =
      Notification.new(%{
        user_id: uid,
        type: :contact,
        title: "Nouvelle demande de contact",
        body: "#{name} souhaite vous ajouter",
        context:
          %{
            "requester_id" => req_id,
            "deep_link" => "/contacts/requests"
          }
          |> maybe_put("request_id", Map.get(event, :request_id))
      })

    deliver(notif)
  end

  def handle_request_received(_), do: :ok

  @spec handle_request_accepted(request_accepted()) :: :ok
  def handle_request_accepted(%{user_id: uid, accepter_id: acc_id} = event)
      when is_binary(uid) and uid != "" and is_binary(acc_id) and acc_id != "" do
    name = Map.get(event, :accepter_display_name) || "Votre contact"

    notif =
      Notification.new(%{
        user_id: uid,
        type: :contact,
        title: "Demande de contact acceptée",
        body: "#{name} a accepté votre demande",
        context:
          %{
            "accepter_id" => acc_id,
            "deep_link" => "/contacts"
          }
          |> maybe_put("request_id", Map.get(event, :request_id))
      })

    deliver(notif)
  end

  def handle_request_accepted(_), do: :ok

  defp deliver(%Notification{user_id: uid} = notif) do
    :ok = History.save(notif)

    if Filter.should_send?(notif) do
      case AuthClient.fetch_devices(uid) do
        {:ok, cache} -> BatchProcessor.deliver(notif, cache)
        _ -> :ok
      end
    else
      :ok
    end
  rescue
    e ->
      Logger.warning("[ContactEvents] deliver raised: #{inspect(e)}")
      :ok
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
