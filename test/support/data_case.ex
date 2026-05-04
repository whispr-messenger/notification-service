defmodule WhisprNotifications.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring access to the
  application's data layer.

  You may define functions here to be used as helpers in your tests.

  Finally, if the test case interacts with the database, we enable the SQL
  sandbox, so changes done to the database are reverted at the end of every
  test.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias WhisprNotifications.Repo

  using do
    quote do
      alias WhisprNotifications.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import WhisprNotifications.DataCase
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
