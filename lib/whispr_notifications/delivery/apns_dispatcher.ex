defmodule WhisprNotifications.Delivery.ApnsDispatcher do
  @moduledoc """
  Dispatcher Pigeon pour Apple Push Notification Service
  (APNS HTTP/2 + JWT ES256).

  Configure au boot par `config/runtime.exs` via `APNS_KEY_PATH`,
  `APNS_KEY_ID`, `APNS_TEAM_ID` et `APNS_MODE`. Ajoute a l'arbre de
  supervision par `WhisprNotifications.Application` uniquement quand
  APNS est entierement configure. Sinon `ApnsClient.send/2` renvoie
  `{:error, :not_configured}`.
  """

  use Pigeon.Dispatcher, otp_app: :whispr_notification
end
