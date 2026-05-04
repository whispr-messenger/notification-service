defmodule WhisprNotifications.ApplicationTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Application, as: App

  test "config_change/3 forwards to the Phoenix endpoint and returns :ok" do
    # `config_change/3` is required by the Application behaviour and is
    # invoked by Phoenix when `Application.put_env` is called at runtime.
    # Just make sure calling it directly returns :ok and doesn't crash.
    assert :ok = App.config_change([], [], [])
  end
end
