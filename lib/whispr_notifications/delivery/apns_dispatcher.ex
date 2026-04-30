defmodule WhisprNotifications.Delivery.ApnsDispatcher do
  @moduledoc """
  Pigeon dispatcher for Apple Push Notification Service (APNS HTTP/2 + JWT ES256).

  Configured at boot by `config/runtime.exs` from `APNS_KEY_PATH`,
  `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_MODE`. Only added to the
  supervision tree by `WhisprNotifications.Application` when APNS is fully
  configured. Otherwise `ApnsClient.send/2` returns `{:error, :not_configured}`.
  """

  use Pigeon.Dispatcher, otp_app: :whispr_notification
end
