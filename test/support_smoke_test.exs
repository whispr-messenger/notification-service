defmodule WhisprNotifications.DataCaseSmokeTest do
  @moduledoc """
  Smoke test that exercises the `WhisprNotifications.DataCase` template so it
  counts toward coverage. The Ecto sandbox setup is run automatically through
  the `using` block + the case `setup` callback.
  """

  use WhisprNotifications.DataCase, async: true

  test "DataCase template boots with a sandboxed Repo" do
    assert Process.whereis(WhisprNotifications.Repo) |> is_pid()
  end
end
