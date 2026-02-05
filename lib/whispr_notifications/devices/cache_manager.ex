defmodule WhisprNotifications.Devices.CacheManager do
  @moduledoc """
  GenServer qui maintient un cache en mémoire des devices des utilisateurs.
  Il utilise AuthClient pour synchroniser.
  """

  use GenServer

  alias WhisprNotifications.Devices.{DeviceCache, AuthClient}

  @type state :: %{String.t() => DeviceCache.t()}

  ## Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec get_cache(String.t()) :: {:ok, DeviceCache.t()} | {:error, term()}
  def get_cache(user_id) do
    GenServer.call(__MODULE__, {:get_cache, user_id})
  end

  @spec refresh_cache(String.t()) :: :ok
  def refresh_cache(user_id) do
    GenServer.cast(__MODULE__, {:refresh_cache, user_id})
  end

  ## Callbacks

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:get_cache, user_id}, _from, state) do
    case Map.fetch(state, user_id) do
      {:ok, cache} ->
        {:reply, {:ok, cache}, state}

      :error ->
        case AuthClient.fetch_devices(user_id) do
          {:ok, cache} ->
            {:reply, {:ok, cache}, Map.put(state, user_id, cache)}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_cast({:refresh_cache, user_id}, state) do
    new_state =
      case AuthClient.fetch_devices(user_id) do
        {:ok, cache} -> Map.put(state, user_id, cache)
        _ -> state
      end

    {:noreply, new_state}
  end
end
