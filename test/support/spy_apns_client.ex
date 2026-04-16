defmodule WhisprNotifications.Test.SpyApnsClient do
  @moduledoc false

  @behaviour WhisprNotifications.Delivery.ApnsClient

  @impl true
  def send(device, payload) do
    test_pid = Application.get_env(:whispr_notification, :apns_spy_pid)

    if test_pid do
      Kernel.send(test_pid, {:apns_send, device, payload})
    end

    case Application.get_env(:whispr_notification, :apns_spy_response) do
      nil -> :ok
      fun when is_function(fun) -> fun.()
      value -> value
    end
  end
end
