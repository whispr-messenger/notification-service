defmodule WhisprNotifications.Auth.JwksCache do
  @moduledoc false
  use GenServer

  alias WhisprNotifications.Auth.Jwks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_key(String.t()) :: {:ok, JOSE.JWK.t()} | :error
  def get_key(kid) when is_binary(kid) do
    GenServer.call(__MODULE__, {:get_key, kid})
  end

  @doc false
  def replace_keys!(%{} = keys_by_kid) do
    :ok = GenServer.call(__MODULE__, {:replace_keys, keys_by_kid})
    :ok
  end

  @impl true
  def init(opts) do
    cond do
      json = opts[:inline_jwks] ->
        case Jwks.keys_from_json(json) do
          {:ok, keys} -> {:ok, %{keys: keys}}
          {:error, reason} -> {:stop, reason}
        end

      url = opts[:url] ->
        case Jwks.fetch_keys(url) do
          {:ok, keys} -> {:ok, %{keys: keys}}
          {:error, reason} -> {:stop, reason}
        end

      opts[:allow_empty] == true ->
        {:ok, %{keys: %{}}}

      true ->
        {:stop, {:bad_jwks_opts, opts}}
    end
  end

  @impl true
  def handle_call({:get_key, kid}, _from, %{keys: keys} = state) do
    reply =
      case Map.get(keys, kid) do
        %JOSE.JWK{} = jwk -> {:ok, jwk}
        _ -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:replace_keys, keys_by_kid}, _from, state) do
    {:reply, :ok, %{state | keys: keys_by_kid}}
  end
end
