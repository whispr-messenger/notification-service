defmodule WhisprNotifications.Devices.CacheManagerTest do
  # Since WHISPR-1159 CacheManager reads the devices table via
  # AuthClient, so we need a shared sandbox to let the long-lived
  # GenServer see the test's transaction.
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Devices.{CacheManager, DeviceCache}

  alias WhisprNotifications.Devices.CacheManagerTest.{
    CountingAuthClient,
    CrashingAuthClient,
    HangingAuthClient,
    SlowAuthClient
  }

  describe "get_cache/1" do
    test "lazily fetches a user's cache via AuthClient when absent" do
      assert {:ok, %DeviceCache{user_id: "cm-user-1", devices: []}} =
               CacheManager.get_cache("cm-user-1")
    end

    test "returns the same cache on subsequent calls (cached)" do
      {:ok, first} = CacheManager.get_cache("cm-user-2")
      {:ok, second} = CacheManager.get_cache("cm-user-2")

      assert first == second
    end

    test "cache hit returns in well under 10ms (no fetch)" do
      # warm up : premier appel chauffe le cache.
      {:ok, _} = CacheManager.get_cache("cm-user-fast")

      {micros, {:ok, _}} =
        :timer.tc(fn -> CacheManager.get_cache("cm-user-fast") end)

      assert micros < 10_000, "cache hit took #{micros}us, expected < 10ms"
    end
  end

  describe "refresh_cache/1" do
    test "returns :ok and updates the state asynchronously" do
      assert :ok = CacheManager.refresh_cache("cm-user-3")

      assert {:ok, %DeviceCache{user_id: "cm-user-3"}} =
               CacheManager.get_cache("cm-user-3")
    end
  end

  describe "concurrency (WHISPR-1361)" do
    setup do
      # remplace le client par un fake qui dort 100ms par fetch. Si la mailbox
      # serialisait les get_cache, 50 calls prendraient au moins 5s. Avec le
      # pattern async_nolink, ils tournent en parallele dans le Task.Supervisor
      # et le total reste sous la seconde.
      previous = Application.get_env(:whispr_notification, :devices_auth_client)

      Application.put_env(:whispr_notification, :devices_auth_client, SlowAuthClient)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:whispr_notification, :devices_auth_client, previous),
          else: Application.delete_env(:whispr_notification, :devices_auth_client)
      end)

      :ok
    end

    test "50 concurrent get_cache for distinct user_ids do not serialize" do
      user_ids = for n <- 1..50, do: "concurrent-user-#{n}"

      {micros, results} =
        :timer.tc(fn ->
          user_ids
          |> Enum.map(fn uid ->
            Task.async(fn -> CacheManager.get_cache(uid, 5_000) end)
          end)
          |> Enum.map(&Task.await(&1, 5_000))
        end)

      # tous les fetchs doivent avoir reussi.
      assert Enum.all?(results, fn
               {:ok, %DeviceCache{}} -> true
               _ -> false
             end)

      # 50 fetchs * 100ms en sequentiel = 5_000ms. En parallele on s'attend
      # a moins de 1s (typiquement 100-200ms). On laisse 1s de marge pour
      # tolerer la CI lente.
      assert micros < 1_000_000,
             "50 parallel fetchs took #{div(micros, 1000)}ms, expected < 1000ms"
    end

    test "concurrent get_cache for same user_id are coalesced (single fetch)" do
      # reset compteur du fake
      SlowAuthClient.reset_count()

      tasks =
        for _ <- 1..10 do
          Task.async(fn -> CacheManager.get_cache("coalesce-user", 5_000) end)
        end

      results = Enum.map(tasks, &Task.await(&1, 5_000))

      assert Enum.all?(results, &match?({:ok, %DeviceCache{user_id: "coalesce-user"}}, &1))

      # single-flight : un seul fetch reel meme avec 10 callers concurrents.
      assert SlowAuthClient.get_count() == 1
    end
  end

  describe "fetch crash handling" do
    setup do
      # client qui crash : on simule un raise qui ferait exploser un Task
      # async_nolink. Le CacheManager doit survivre et repondre a tous les
      # waiters avec {:error, {:fetch_crashed, _}}.
      previous = Application.get_env(:whispr_notification, :devices_auth_client)

      Application.put_env(:whispr_notification, :devices_auth_client, CrashingAuthClient)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:whispr_notification, :devices_auth_client, previous),
          else: Application.delete_env(:whispr_notification, :devices_auth_client)
      end)

      :ok
    end

    test "fetch crash returns {:error, {:fetch_crashed, _}} and CacheManager survives" do
      # CrashingAuthClient raise volontairement. Avec async_nolink, le
      # CacheManager n'est pas tue. Les waiters sont notifies via le DOWN.
      assert {:error, {:fetch_crashed, _reason}} =
               CacheManager.get_cache("crash-user", 5_000)

      # le GenServer principal doit toujours etre vivant.
      assert Process.alive?(Process.whereis(CacheManager))
    end
  end

  describe "DOWN handler robustness" do
    test "DOWN with unknown ref logs warn and leaves state unchanged" do
      pid = Process.whereis(CacheManager)
      state_before = :sys.get_state(pid)

      # envoie un DOWN avec une ref jamais enregistree dans ref_to_user
      ref = make_ref()
      send(pid, {:DOWN, ref, :process, self(), :normal})

      # laisse le GenServer traiter le message
      _ = :sys.get_state(pid)

      state_after = :sys.get_state(pid)

      assert state_before.inflight == state_after.inflight
      assert state_before.ref_to_user == state_after.ref_to_user
      assert Process.alive?(pid)
    end

    test "result for unknown ref logs warn and leaves state unchanged" do
      pid = Process.whereis(CacheManager)
      state_before = :sys.get_state(pid)

      # envoie un message {ref, result} avec une ref inconnue
      ref = make_ref()
      send(pid, {ref, {:ok, %DeviceCache{user_id: "phantom", devices: []}}})

      _ = :sys.get_state(pid)

      state_after = :sys.get_state(pid)

      # le cache phantom NE doit PAS avoir ete ajoute
      refute Map.has_key?(state_after.caches, "phantom")
      assert state_before.inflight == state_after.inflight
      assert state_before.ref_to_user == state_after.ref_to_user
      assert Process.alive?(pid)
    end
  end

  describe "TTL refresh (WHISPR-1394)" do
    setup do
      # client qui compte les fetchs : on doit en voir 2 (initial + refresh
      # async declenche par stale entry).
      previous = Application.get_env(:whispr_notification, :devices_auth_client)

      Application.put_env(:whispr_notification, :devices_auth_client, CountingAuthClient)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:whispr_notification, :devices_auth_client, previous),
          else: Application.delete_env(:whispr_notification, :devices_auth_client)
      end)

      :ok
    end

    test "stale entry triggers async refresh and serves the existing value" do
      CountingAuthClient.reset_count()

      # premier appel : cache miss, fetch sync (compteur = 1).
      assert {:ok, _} = CacheManager.get_cache("ttl-user", 5_000)

      # on force l'entry a etre stale en backdating fetched_at.
      pid = Process.whereis(CacheManager)

      :sys.replace_state(pid, fn state ->
        backdated = %DeviceCache{
          state.caches["ttl-user"]
          | fetched_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        }

        put_in(state, [:caches, "ttl-user"], backdated)
      end)

      # 2eme appel : cache hit stale, on renvoie la valeur connue ET on
      # declenche un refresh async (compteur passe a 2).
      assert {:ok, _} = CacheManager.get_cache("ttl-user", 5_000)

      # laisse le Task async se terminer.
      _ = :sys.get_state(pid)
      Process.sleep(50)
      _ = :sys.get_state(pid)

      assert CountingAuthClient.get_count() == 2

      # apres le refresh, l'entry doit avoir un fetched_at recent.
      state = :sys.get_state(pid)
      cache = state.caches["ttl-user"]
      assert %DateTime{} = cache.fetched_at
      assert DateTime.diff(DateTime.utc_now(), cache.fetched_at, :second) < 5
    end
  end

  describe "timeout handling" do
    setup do
      # client qui dort 5s : aucun get_cache(_, 200ms) ne peut reussir a temps.
      previous = Application.get_env(:whispr_notification, :devices_auth_client)

      Application.put_env(:whispr_notification, :devices_auth_client, HangingAuthClient)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:whispr_notification, :devices_auth_client, previous),
          else: Application.delete_env(:whispr_notification, :devices_auth_client)
      end)

      :ok
    end

    test "get_cache with explicit short timeout returns {:error, :timeout}" do
      assert {:error, :timeout} = CacheManager.get_cache("hang-user", 200)
    end
  end
end

defmodule WhisprNotifications.Devices.CacheManagerTest.SlowAuthClient do
  @moduledoc false
  alias WhisprNotifications.Devices.DeviceCache

  @behaviour WhisprNotifications.Devices.AuthClient

  # compteur partage pour verifier le single-flight.
  def reset_count do
    if :ets.whereis(__MODULE__) == :undefined do
      :ets.new(__MODULE__, [:public, :named_table])
    end

    :ets.insert(__MODULE__, {:count, 0})
  end

  def get_count do
    case :ets.lookup(__MODULE__, :count) do
      [{:count, n}] -> n
      _ -> 0
    end
  end

  @impl true
  def fetch_devices(user_id) do
    if :ets.whereis(__MODULE__) != :undefined do
      :ets.update_counter(__MODULE__, :count, 1, {:count, 0})
    end

    Process.sleep(100)
    {:ok, %DeviceCache{user_id: user_id, devices: []}}
  end
end

defmodule WhisprNotifications.Devices.CacheManagerTest.HangingAuthClient do
  @moduledoc false
  alias WhisprNotifications.Devices.DeviceCache

  @behaviour WhisprNotifications.Devices.AuthClient

  @impl true
  def fetch_devices(user_id) do
    Process.sleep(5_000)
    {:ok, %DeviceCache{user_id: user_id, devices: []}}
  end
end

defmodule WhisprNotifications.Devices.CacheManagerTest.CrashingAuthClient do
  @moduledoc false
  @behaviour WhisprNotifications.Devices.AuthClient

  @impl true
  def fetch_devices(_user_id) do
    raise "simulated crash"
  end
end

defmodule WhisprNotifications.Devices.CacheManagerTest.CountingAuthClient do
  @moduledoc false
  alias WhisprNotifications.Devices.DeviceCache

  @behaviour WhisprNotifications.Devices.AuthClient

  def reset_count do
    if :ets.whereis(__MODULE__) == :undefined do
      :ets.new(__MODULE__, [:public, :named_table])
    end

    :ets.insert(__MODULE__, {:count, 0})
  end

  def get_count do
    case :ets.lookup(__MODULE__, :count) do
      [{:count, n}] -> n
      _ -> 0
    end
  end

  @impl true
  def fetch_devices(user_id) do
    if :ets.whereis(__MODULE__) != :undefined do
      :ets.update_counter(__MODULE__, :count, 1, {:count, 0})
    end

    {:ok, %DeviceCache{user_id: user_id, devices: []}}
  end
end
