defmodule WhisprNotifications.Test.SpyWebPushClient do
  @moduledoc false

  @behaviour WhisprNotifications.Delivery.WebPushClient

  @impl true
  def send(device, payload) do
    test_pid = Application.get_env(:whispr_notification, :web_push_spy_pid)

    if test_pid do
      Kernel.send(test_pid, {:web_push_send, device, payload})
    end

    case Application.get_env(:whispr_notification, :web_push_spy_response) do
      nil -> :ok
      fun when is_function(fun, 0) -> fun.()
      value -> value
    end
  end
end
