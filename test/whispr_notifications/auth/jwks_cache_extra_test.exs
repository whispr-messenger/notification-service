defmodule WhisprNotifications.Auth.JwksCacheExtraTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Auth.{Jwks, JwksCache}
  alias WhisprNotifications.Test.ES256JwtFixtures

  # Clear any :jwt config left by other tests so options-only paths are exercised.
  setup do
    previous = Application.get_env(:whispr_notification, :jwt)
    Application.delete_env(:whispr_notification, :jwt)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:whispr_notification, :jwt)
      else
        Application.put_env(:whispr_notification, :jwt, previous)
      end
    end)

    :ok
  end

  test "start_link/1 supports :inline_jwks option" do
    inline = Jason.encode!(%{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]})
    server = :jwks_cache_inline_test

    start_supervised!({JwksCache, [name: server, inline_jwks: inline]})

    assert {:ok, %JOSE.JWK{}} = JwksCache.get_key(ES256JwtFixtures.primary_kid(), server)
  end

  test "start_link/1 supports :allow_empty" do
    server = :jwks_cache_empty_test

    start_supervised!({JwksCache, [name: server, allow_empty: true]})

    assert {:error, :unknown_kid} = JwksCache.get_key("anything", server)
  end

  test "handle_call({:replace_keys, map}) swaps the key set" do
    server = :jwks_cache_replace_test
    start_supervised!({JwksCache, [name: server, allow_empty: true]})

    inline = Jason.encode!(%{"keys" => [ES256JwtFixtures.primary_jwks_public_entry()]})
    {:ok, keys} = Jwks.keys_from_json(inline)

    assert :ok = GenServer.call(server, {:replace_keys, keys})
    assert {:ok, %JOSE.JWK{}} = JwksCache.get_key(ES256JwtFixtures.primary_kid(), server)
  end

  test "http_get_fun returning non-200 bubbles up as {:http, status}" do
    server = :jwks_cache_http_error_test
    http_get_fun = fn _ -> {:ok, %{status: 503}} end

    Process.flag(:trap_exit, true)

    assert {:error, {:http, 503}} =
             JwksCache.start_link(
               name: server,
               jwks_url: "http://x",
               http_get_fun: http_get_fun
             )
  end

  test "http_get_fun returning :error tuple bubbles up" do
    server = :jwks_cache_http_err2_test
    http_get_fun = fn _ -> {:error, :econnrefused} end

    Process.flag(:trap_exit, true)

    assert {:error, :econnrefused} =
             JwksCache.start_link(
               name: server,
               jwks_url: "http://x",
               http_get_fun: http_get_fun
             )
  end

  test "http_get_fun returning unexpected shape is wrapped in :bad_http_result" do
    server = :jwks_cache_http_weird_test
    http_get_fun = fn _ -> :nope end

    Process.flag(:trap_exit, true)

    assert {:error, {:bad_http_result, :nope}} =
             JwksCache.start_link(
               name: server,
               jwks_url: "http://x",
               http_get_fun: http_get_fun
             )
  end

  test "without any option and without jwks_url returns :bad_jwks_opts" do
    server = :jwks_cache_no_opts_test
    Process.flag(:trap_exit, true)

    assert {:error, {:bad_jwks_opts, _}} = JwksCache.start_link(name: server)
  end
end
