defmodule WhisprNotifications.Auth.JwksCache do
  @moduledoc false
  use GenServer
  require Logger

  alias WhisprNotifications.Auth.Jwks

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_key(String.t(), GenServer.server()) ::
          {:ok, JOSE.JWK.t()} | {:error, :unknown_kid}
  def get_key(kid, server \\ __MODULE__) when is_binary(kid) do
    GenServer.call(server, {:get_key, kid})
  end

  @doc false
  def replace_keys!(%{} = keys_by_kid) do
    :ok = GenServer.call(__MODULE__, {:replace_keys, keys_by_kid})
    :ok
  end

  @impl true
  def init(opts) do
    refresh_ms = Keyword.get(opts, :refresh_interval_ms)
    jwks_url = resolve_jwks_url(opts)
    http_get_fun = Keyword.get(opts, :http_get_fun)

    case load_keys(opts, jwks_url, http_get_fun) do
      {:ok, keys} ->
        state = %{
          keys: keys,
          refresh_interval_ms: refresh_ms,
          jwks_url: jwks_url,
          http_get_fun: http_get_fun
        }

        schedule_refresh(refresh_ms)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp resolve_jwks_url(opts) do
    Keyword.get(opts, :jwks_url) ||
      Keyword.get(opts, :url) ||
      get_in(Application.get_env(:whispr_notification, :jwt, []), [:jwks_url])
  end

  defp load_keys(opts, jwks_url, http_get_fun) do
    cond do
      json = opts[:inline_jwks] -> Jwks.keys_from_json(json)
      is_function(http_get_fun, 1) -> load_via_http(jwks_url, http_get_fun)
      opts[:allow_empty] == true -> {:ok, %{}}
      is_binary(jwks_url) and jwks_url != "" -> Jwks.fetch_keys(jwks_url)
      true -> {:error, {:bad_jwks_opts, opts}}
    end
  end

  defp load_via_http(jwks_url, http_get_fun) do
    case http_get_fun.(jwks_url || "") do
      {:ok, %{status: 200, body: body}} ->
        body_json = if is_binary(body), do: body, else: Jason.encode!(body)
        Jwks.keys_from_json(body_json)

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:bad_http_result, other}}
    end
  end

  @impl true
  def handle_call({:get_key, kid}, _from, %{keys: keys} = state) do
    reply =
      case Map.get(keys, kid) do
        %JOSE.JWK{} = jwk -> {:ok, jwk}
        _ -> {:error, :unknown_kid}
      end

    {:reply, reply, state}
  end

  def handle_call({:replace_keys, keys_by_kid}, _from, state) do
    {:reply, :ok, %{state | keys: keys_by_kid}}
  end

  @impl true
  def handle_info(:refresh, state) do
    new_keys =
      case refresh_keys(state) do
        {:ok, keys} when map_size(keys) > 0 ->
          Logger.info("[JwksCache] Refreshed #{map_size(keys)} key(s)")
          keys

        {:ok, _empty} ->
          Logger.warning("[JwksCache] Refresh returned no keys — keeping previous set")
          state.keys

        {:error, reason} ->
          Logger.error(
            "[JwksCache] Refresh failed: #{inspect(reason)} — keeping previous set"
          )

          state.keys
      end

    schedule_refresh(state.refresh_interval_ms)
    {:noreply, %{state | keys: new_keys}}
  end

  # Periodic refresh re-uses the same HTTP path as boot, but never falls back
  # to :inline_jwks (one-shot, set by Application prefetch only) or :allow_empty
  # (boot-only escape hatch). When no fetch source is configured we just no-op
  # and re-arm the timer so the cache can later be repopulated via replace_keys!.
  defp refresh_keys(%{http_get_fun: fun, jwks_url: url}) when is_function(fun, 1),
    do: load_via_http(url, fun)

  defp refresh_keys(%{jwks_url: url}) when is_binary(url) and url != "",
    do: Jwks.fetch_keys(url)

  defp refresh_keys(_), do: {:ok, %{}}

  defp schedule_refresh(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :refresh, ms)
    :ok
  end

  defp schedule_refresh(_), do: :ok
end
