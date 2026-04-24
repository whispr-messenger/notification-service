defmodule WhisprNotifications.Delivery.FcmDispatcher do
  @moduledoc """
  Pigeon dispatcher for Firebase Cloud Messaging (HTTP v1).

  Configured at boot by `config/runtime.exs` from `FCM_PROJECT_ID` +
  `FCM_JSON_KEYFILE` / `FCM_JSON`. Only added to the supervision tree by
  `WhisprNotifications.Application` when FCM is fully configured.
  """

  use Pigeon.Dispatcher, otp_app: :whispr_notification
end
