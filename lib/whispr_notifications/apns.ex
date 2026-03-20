defmodule WhisprNotifications.APNS do
  @moduledoc """
  Pigeon dispatcher for APNS.
  """

  use Pigeon.Dispatcher, otp_app: :whispr_notification
end
