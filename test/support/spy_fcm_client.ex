defmodule WhisprNotifications.Test.SpyFcmClient do
  @moduledoc false

  @behaviour WhisprNotifications.Delivery.FcmClient

  @impl true
  def send(device, payload) do
    test_pid = Application.get_env(:whispr_notification, :fcm_spy_pid)

    if test_pid do
      Kernel.send(test_pid, {:fcm_send, device, payload})
    end

    :ok
  end
end
