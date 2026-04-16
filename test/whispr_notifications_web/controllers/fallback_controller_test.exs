defmodule WhisprNotificationsWeb.FallbackControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WhisprNotificationsWeb.FallbackController

  test "call/2 with :not_found returns 404" do
    conn = :get |> conn("/") |> FallbackController.call({:error, :not_found})
    assert conn.status == 404
  end

  test "call/2 with :bad_request returns 400" do
    conn = :get |> conn("/") |> FallbackController.call({:error, :bad_request})
    assert conn.status == 400
  end

  test "call/2 with unknown error returns 500" do
    conn = :get |> conn("/") |> FallbackController.call({:error, :kaboom})
    assert conn.status == 500
  end
end
