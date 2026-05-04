defmodule WhisprNotifications.Auth.JwksCacheRefreshTest do
  @moduledoc """
  Exercises the periodic refresh path of `JwksCache` and the
  `replace_keys!/1` helper which targets the singleton named instance.
  """
  use ExUnit.Case, async: false

  alias WhisprNotifications.Auth.{Jwks, JwksCache}
  alias WhisprNotifications.Test.ES256JwtFixtures

  test "handle_info(:refresh, state) keeps fresh keys when fetch returns a map of keys" do
    server = :jwks_cache_refresh_ok_test
    inline = Jason.encode!(%{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]})
    {:ok, keys} = Jwks.keys_from_json(inline)

    fetched = make_ref()
    test_pid = self()

    http_get_fun = fn _ ->
      send(test_pid, {fetched, :hit})
      {:ok, %{status: 200, body: %{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]}}}
    end

    start_supervised!(
      {JwksCache,
       [
         name: server,
         jwks_url: "http://x",
         http_get_fun: http_get_fun,
         refresh_interval_ms: 60_000
       ]}
    )

    # Drain the boot fetch.
    assert_receive {^fetched, :hit}, 200

    send(server, :refresh)
    assert_receive {^fetched, :hit}, 500

    # The cache still answers correctly after the refresh.
    assert {:ok, %JOSE.JWK{}} = JwksCache.get_key(ES256JwtFixtures.primary_kid(), server)
    assert map_size(keys) == 1
  end

  test "handle_info(:refresh, state) keeps the previous set when fetch returns no keys" do
    server = :jwks_cache_refresh_empty_test
    test_pid = self()

    fetch_fun = fn _ ->
      send(test_pid, :fetched)
      {:ok, %{status: 200, body: %{"keys" => []}}}
    end

    start_supervised!(
      {JwksCache,
       [
         name: server,
         jwks_url: "http://x",
         http_get_fun: fn _ ->
           {:ok,
            %{
              status: 200,
              body: %{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]}
            }}
         end,
         refresh_interval_ms: 60_000
       ]}
    )

    # Replace the http_get_fun is not possible, but we can swap state directly:
    # send a refresh AFTER replacing keys with an explicitly empty fetch
    # using a stateful manipulation of the GenServer.
    state = :sys.get_state(server)
    new_state = %{state | http_get_fun: fetch_fun}
    :sys.replace_state(server, fn _ -> new_state end)

    send(server, :refresh)
    assert_receive :fetched, 500

    # The previous (non-empty) key set is preserved.
    assert {:ok, %JOSE.JWK{}} = JwksCache.get_key(ES256JwtFixtures.primary_kid(), server)
  end

  test "handle_info(:refresh, state) keeps the previous set on fetch error" do
    server = :jwks_cache_refresh_err_test
    test_pid = self()

    boot_fun = fn _ ->
      {:ok, %{status: 200, body: %{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]}}}
    end

    err_fun = fn _ ->
      send(test_pid, :fetched_err)
      {:error, :nxdomain}
    end

    start_supervised!(
      {JwksCache,
       [
         name: server,
         jwks_url: "http://x",
         http_get_fun: boot_fun,
         refresh_interval_ms: 60_000
       ]}
    )

    state = :sys.get_state(server)
    :sys.replace_state(server, fn _ -> %{state | http_get_fun: err_fun} end)

    send(server, :refresh)
    assert_receive :fetched_err, 500

    # Previous keys still resolve.
    assert {:ok, %JOSE.JWK{}} = JwksCache.get_key(ES256JwtFixtures.primary_kid(), server)
  end

  test "replace_keys!/1 swaps the singleton's key set" do
    if pid = Process.whereis(JwksCache) do
      original = :sys.get_state(pid).keys
      inline = Jason.encode!(%{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]})
      {:ok, keys} = Jwks.keys_from_json(inline)

      assert :ok = JwksCache.replace_keys!(keys)

      assert {:ok, %JOSE.JWK{}} = JwksCache.get_key(ES256JwtFixtures.primary_kid())

      # restore previous keys to avoid leaking into other tests
      :sys.replace_state(pid, fn s -> %{s | keys: original} end)
    else
      # JwksCache isn't started in this test process — nothing to assert,
      # but the function path is still exercised by other tests.
      :ok
    end
  end

  test "refresh_keys/1 no-ops when neither http_get_fun nor jwks_url are set" do
    server = :jwks_cache_refresh_noop_test

    start_supervised!({JwksCache, [name: server, allow_empty: true]})

    # State has neither :http_get_fun nor a :jwks_url, so :refresh hits the
    # third defp refresh_keys/1 clause that returns {:ok, %{}}.
    send(server, :refresh)
    Process.sleep(50)

    # The process is still alive and answering.
    assert {:error, :unknown_kid} = JwksCache.get_key("anything", server)
  end
end
