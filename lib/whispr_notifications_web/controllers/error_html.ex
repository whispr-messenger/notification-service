defmodule WhisprNotificationsWeb.ErrorHTML do
  def render(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)
    "Error: #{status}"
  end
end
