defmodule WhisprNotifications.Devices.CacheManager do
  @moduledoc """
  GenServer qui maintient un cache en memoire des devices des utilisateurs.

  ## Pourquoi le pattern async

  Sur cache miss, le fetch (Ecto + parfois HTTP via AuthClient) prenait plusieurs
  centaines de ms a quelques secondes. Comme le GenServer est un singleton
  nomme, tous les `get_cache/1` etaient serialises dans la mailbox. Sur une
  rafale (50 messages dans un groupe = 50 lookups), cela cascadait en timeouts
  (default 5s) et bloquait toute la livraison de notifs.

  Solution : on repond toujours `{:noreply, state}` immediatement au caller
  via `from`, on lance le fetch dans un `Task.Supervisor` (un Task par user_id),
  et c'est le `handle_info` qui repond avec `GenServer.reply(from, result)`
  quand le fetch finit. La mailbox reste libre pour traiter les autres
  `get_cache/1` en parallele.

  On coalesce aussi les requetes concurrentes pour le meme user_id (single-flight) :
  si deux callers demandent le cache du meme user pendant un fetch, le 2eme
  attend la reponse du fetch en cours au lieu d'en lancer un nouveau.
  """

  use GenServer

  alias WhisprNotifications.Devices.{AuthClient, DeviceCache}

  # default timeout cote caller : volontairement plus court que le 5s default
  # de GenServer.call pour que les call sites coupent court avant que la
  # mailbox du caller (BatchProcessor, etc.) ne sature.
  @default_get_timeout 3_000

  # client par defaut. Configurable via :whispr_notification, :devices_auth_client
  # pour permettre l'injection de fakes en test (cf. cache_manager_test.exs).
  @default_auth_client AuthClient

  # nom du Task.Supervisor qui isole les fetchs : un crash de fetch n'impacte
  # pas le CacheManager (async_nolink) ni les autres fetchs (one_for_one).
  @task_supervisor WhisprNotifications.Devices.CacheManager.TaskSupervisor

  @type state :: %{
          caches: %{String.t() => DeviceCache.t()},
          # user_id => {task_ref, [from1, from2, ...]} : les callers en attente
          # du fetch en cours pour ce user_id. Permet de coalesce les requetes.
          inflight: %{String.t() => {reference(), [GenServer.from()]}},
          # task_ref => user_id : index inverse pour retrouver le user_id
          # quand un Task termine (DOWN ou {ref, result}).
          ref_to_user: %{reference() => String.t()}
        }

  ## Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Recupere le cache devices d'un utilisateur. Sur cache miss, lance un
  fetch async et bloque le caller jusqu'a `timeout` ms.

  Le timeout par defaut (#{@default_get_timeout} ms) est plus court que le
  default de `GenServer.call` (5_000 ms) pour eviter qu'un caller bloque
  trop longtemps en cas de DB lente.
  """
  @spec get_cache(String.t(), timeout()) :: {:ok, DeviceCache.t()} | {:error, term()}
  def get_cache(user_id, timeout \\ @default_get_timeout) do
    GenServer.call(__MODULE__, {:get_cache, user_id}, timeout)
  catch
    # GenServer.call leve un :exit en cas de timeout. on le traduit en
    # {:error, :timeout} pour que les call sites n'aient pas a se proteger
    # avec un try/catch.
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @spec refresh_cache(String.t()) :: :ok
  def refresh_cache(user_id) do
    GenServer.cast(__MODULE__, {:refresh_cache, user_id})
  end

  ## Callbacks

  @impl true
  def init(_state) do
    # on demarre le Task.Supervisor sous le meme arbre. start_link de
    # Task.Supervisor en init/1 est sur, on est encore dans le boot du
    # CacheManager donc personne ne nous appelle encore.
    {:ok, _} = Task.Supervisor.start_link(name: @task_supervisor)

    {:ok, %{caches: %{}, inflight: %{}, ref_to_user: %{}}}
  end

  @impl true
  def handle_call({:get_cache, user_id}, from, state) do
    case Map.fetch(state.caches, user_id) do
      {:ok, cache} ->
        # cache hit : reply sync, pas de fetch.
        {:reply, {:ok, cache}, state}

      :error ->
        # cache miss : on enregistre le caller comme waiter et on lance
        # (ou on rejoint) un fetch async. {:noreply, state} libere la
        # mailbox pour traiter les autres get_cache pendant le fetch.
        {:noreply, enqueue_waiter(state, user_id, from)}
    end
  end

  @impl true
  def handle_cast({:refresh_cache, user_id}, state) do
    # refresh est fire-and-forget : pas de waiters, on ecrit le resultat
    # dans le cache uniquement si le fetch reussit.
    new_state =
      case auth_client().fetch_devices(user_id) do
        {:ok, cache} -> put_in(state, [:caches, user_id], cache)
        _ -> state
      end

    {:noreply, new_state}
  end

  # Reception du resultat d'un Task lance par enqueue_waiter/3.
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.ref_to_user, ref) do
      {nil, _} ->
        # ref inconnue (Task lance avant un crash, ou monitor deja consomme).
        {:noreply, state}

      {user_id, ref_to_user} ->
        # on a recu le resultat avant le DOWN : on demonitor pour eviter
        # de recevoir le DOWN apres coup et de re-traiter le user_id.
        Process.demonitor(ref, [:flush])

        {_ref, waiters} = Map.fetch!(state.inflight, user_id)
        Enum.each(waiters, &GenServer.reply(&1, result))

        new_caches =
          case result do
            {:ok, cache} -> Map.put(state.caches, user_id, cache)
            _ -> state.caches
          end

        {:noreply,
         %{
           state
           | caches: new_caches,
             inflight: Map.delete(state.inflight, user_id),
             ref_to_user: ref_to_user
         }}
    end
  end

  # Le Task a crashe (raise non rescue, exit). async_nolink garantit qu'on
  # ne meurt pas avec lui. On repond {:error, :fetch_crashed} aux waiters.
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    case Map.pop(state.ref_to_user, ref) do
      {nil, _} ->
        {:noreply, state}

      {user_id, ref_to_user} ->
        {_ref, waiters} = Map.fetch!(state.inflight, user_id)
        Enum.each(waiters, &GenServer.reply(&1, {:error, {:fetch_crashed, reason}}))

        {:noreply,
         %{
           state
           | inflight: Map.delete(state.inflight, user_id),
             ref_to_user: ref_to_user
         }}
    end
  end

  ## Internals

  # Ajoute un caller a la liste des waiters pour ce user_id, en lancant
  # un Task de fetch si aucun n'est encore en cours (single-flight).
  defp enqueue_waiter(state, user_id, from) do
    case Map.fetch(state.inflight, user_id) do
      {:ok, {ref, waiters}} ->
        # un fetch est deja en cours : on rejoint la file d'attente.
        put_in(state.inflight[user_id], {ref, [from | waiters]})

      :error ->
        # aucun fetch en cours : on en lance un.
        task =
          Task.Supervisor.async_nolink(@task_supervisor, auth_client(), :fetch_devices, [user_id])

        %{
          state
          | inflight: Map.put(state.inflight, user_id, {task.ref, [from]}),
            ref_to_user: Map.put(state.ref_to_user, task.ref, user_id)
        }
    end
  end

  defp auth_client do
    Application.get_env(:whispr_notification, :devices_auth_client, @default_auth_client)
  end
end
