defmodule WhisprNotificationsWeb do
  def controller do
    quote do
      use Phoenix.Controller, namespace: WhisprNotificationsWeb

      import Plug.Conn
      alias WhisprNotificationsWeb.Router.Helpers, as: Routes
      action_fallback WhisprNotificationsWeb.FallbackController
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/whispr_notifications_web/templates",
        namespace: WhisprNotificationsWeb

      import Phoenix.Controller, only: [view_module: 1, view_template: 1]
      alias WhisprNotificationsWeb.Router.Helpers, as: Routes
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
