defmodule WhisprNotifications.Auth.JwksCache do
  @moduledoc """
  Caches JWKS keys and refreshes them periodically.
  """

  use GenServer

  require Logger

  @default_refresh_interval_ms :timer.minutes(5)

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_key(String.t(), GenServer.server()) :: {:ok, JOSE.JWK.t()} | {:error, :unknown_kid}
  def get_key(kid, server \\ __MODULE__) when is_binary(kid) do
    GenServer.call(server, {:get_key, kid})
  end

  @spec refresh(GenServer.server()) :: :ok
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  @impl true
  def init(opts) do
    state = %{
      keys_by_kid: %{},
      jwks_url: Keyword.get(opts, :jwks_url, jwks_url()),
      refresh_interval_ms: Keyword.get(opts, :refresh_interval_ms, refresh_interval_ms()),
      http_get_fun: Keyword.get(opts, :http_get_fun, &Req.get/1)
    }
    state = fetch_and_store(state)
    schedule_refresh(state.refresh_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:get_key, kid}, _from, state) do
    case Map.fetch(state.keys_by_kid, kid) do
      {:ok, key} -> {:reply, {:ok, key}, state}
      :error -> {:reply, {:error, :unknown_kid}, state}
    end
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, fetch_and_store(state)}
  end

  @impl true
  def handle_info(:refresh, state) do
    new_state = fetch_and_store(state)
    schedule_refresh(new_state.refresh_interval_ms)
    {:noreply, new_state}
  end

  defp fetch_and_store(%{jwks_url: nil} = state), do: state
  defp fetch_and_store(%{jwks_url: ""} = state), do: state

  defp fetch_and_store(state) do
    case fetch_jwks(state.jwks_url, state.http_get_fun) do
      {:ok, keys_by_kid} ->
        Logger.info("JWKS cache refreshed with #{map_size(keys_by_kid)} keys")
        %{state | keys_by_kid: keys_by_kid}

      {:error, reason} ->
        Logger.warning("Failed to refresh JWKS cache: #{inspect(reason)}")
        state
    end
  end

  defp fetch_jwks(url, http_get_fun) do
    with {:ok, %{status: 200, body: body}} <- http_get_fun.(url),
         {:ok, keys} <- extract_keys(body) do
      {:ok, build_keys_by_kid(keys)}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  defp extract_keys(%{"keys" => keys}) when is_list(keys), do: {:ok, keys}

  defp extract_keys(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"keys" => keys}} when is_list(keys) -> {:ok, keys}
      _ -> {:error, :invalid_jwks_payload}
    end
  end

  defp extract_keys(_), do: {:error, :invalid_jwks_payload}

  defp build_keys_by_kid(keys) do
    keys
    |> Enum.reduce(%{}, fn key_map, acc ->
      normalized = stringify_keys(key_map)

      case normalized do
        %{"kid" => kid} when is_binary(kid) ->
          case JOSE.JWK.from_map(normalized) do
            %JOSE.JWK{} = jwk -> Map.put(acc, kid, jwk)
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp schedule_refresh(interval_ms), do: Process.send_after(self(), :refresh, interval_ms)

  defp jwks_url do
    Application.get_env(:whispr_notification, :jwt, [])
    |> Keyword.get(:jwks_url)
  end

  defp refresh_interval_ms do
    Application.get_env(:whispr_notification, :jwt, [])
    |> Keyword.get(:jwks_refresh_interval_ms, @default_refresh_interval_ms)
  end
end
