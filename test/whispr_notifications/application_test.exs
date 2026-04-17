defmodule WhisprNotifications.ApplicationTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Application, as: App

  test "config_change/3 is a no-op returning :ok" do
    assert :ok = App.config_change([], %{}, [])
  end
end
