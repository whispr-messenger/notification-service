defmodule WhisprNotifications.ApplicationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias WhisprNotifications.Application, as: App

  defmodule TestPlug do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(%Plug.Conn{} = conn, opts) do
      ref = Keyword.fetch!(opts, :ref)

      case :persistent_term.get({__MODULE__, ref}, :ok) do
        {:status, status, body} ->
          conn |> Plug.Conn.resp(status, body) |> Plug.Conn.send_resp()

        :ok ->
          conn |> Plug.Conn.resp(200, ~s|{"keys":[]}|) |> Plug.Conn.send_resp()
      end
    end
  end

  defp start_test_server(ref, response \\ :ok) do
    :persistent_term.put({TestPlug, ref}, response)
    {:ok, _pid} = Plug.Cowboy.http(TestPlug, [ref: ref], port: 0, ref: ref)
    port = :ranch.get_port(ref)

    ExUnit.Callbacks.on_exit(fn ->
      Plug.Cowboy.shutdown(ref)
      :persistent_term.erase({TestPlug, ref})
    end)

    port
  end

  test "config_change/3 forwards to the Phoenix endpoint and returns :ok" do
    # `config_change/3` is required by the Application behaviour and is
    # invoked by Phoenix when `Application.put_env` is called at runtime.
    # Just make sure calling it directly returns :ok and doesn't crash.
    assert :ok = App.config_change([], [], [])
  end

  describe "prefetch_jwks/1" do
    test "returns :unconfigured for nil/empty url (catch-all clause)" do
      assert :unconfigured = App.prefetch_jwks(nil)
      assert :unconfigured = App.prefetch_jwks("")
      assert :unconfigured = App.prefetch_jwks(:not_a_string)
    end

    test "returns {:error, _} when the JWKS endpoint is unreachable" do
      # Use a port that's almost certainly closed locally so Req errors
      # without going through the network.
      assert {:error, _reason} = App.prefetch_jwks("http://127.0.0.1:1/jwks.json")
    end

    test "returns {:error, {:http, status}} for non-200 responses" do
      port = start_test_server(:jwks_503, {:status, 503, ~s|{"err":"nope"}|})
      assert {:error, {:http, 503}} = App.prefetch_jwks("http://127.0.0.1:#{port}/jwks.json")
    end

    test "returns {:ok, body} on 200 with binary body" do
      port = start_test_server(:jwks_ok)
      assert {:ok, body} = App.prefetch_jwks("http://127.0.0.1:#{port}/jwks.json")
      assert is_binary(body)
      assert body =~ ~s|"keys"|
    end
  end

  describe "fcm_children/0 + apns_children/0" do
    setup do
      previous_fcm = Application.get_env(:whispr_notification, :fcm)
      previous_apns = Application.get_env(:whispr_notification, :apns)

      on_exit(fn ->
        restore(:fcm, previous_fcm)
        restore(:apns, previous_apns)
      end)

      :ok
    end

    test "fcm_children is empty when :enabled is false" do
      Application.put_env(:whispr_notification, :fcm, enabled: false)
      assert App.fcm_children() == []
    end

    test "fcm_children is empty when :credentials is missing" do
      Application.put_env(:whispr_notification, :fcm, enabled: true)
      assert App.fcm_children() == []
    end

    test "fcm_children returns Goth + FcmDispatcher specs when fully configured" do
      Application.put_env(:whispr_notification, :fcm,
        enabled: true,
        credentials: %{"type" => "service_account", "project_id" => "p"}
      )

      assert [{Goth, _opts}, WhisprNotifications.Delivery.FcmDispatcher] = App.fcm_children()
    end

    test "apns_children is empty when :enabled is false" do
      Application.put_env(:whispr_notification, :apns, enabled: false)
      assert App.apns_children() == []
    end

    test "apns_children returns the dispatcher spec when :enabled is true" do
      Application.put_env(:whispr_notification, :apns, enabled: true)
      assert [WhisprNotifications.Delivery.ApnsDispatcher] = App.apns_children()
    end
  end

  describe "jwks_cache_opts/0" do
    setup do
      previous = Application.get_env(:whispr_notification, :jwt)
      on_exit(fn -> restore(:jwt, previous) end)
      :ok
    end

    test "returns allow_empty when no jwks_url is configured (:unconfigured branch)" do
      Application.put_env(:whispr_notification, :jwt, refresh_interval_ms: 1234)

      opts = App.jwks_cache_opts()
      assert Keyword.get(opts, :allow_empty) == true
      assert Keyword.get(opts, :refresh_interval_ms) == 1234
    end

    test "returns allow_empty + jwks_url and logs a warning when prefetch fails" do
      Application.put_env(:whispr_notification, :jwt,
        jwks_url: "http://127.0.0.1:1/jwks.json",
        refresh_interval_ms: 5_000
      )

      log =
        capture_log(fn ->
          opts = App.jwks_cache_opts()
          assert Keyword.get(opts, :allow_empty) == true
          assert Keyword.get(opts, :jwks_url) == "http://127.0.0.1:1/jwks.json"
        end)

      assert log =~ "JWKS prefetch"
    end

    test "returns inline_jwks + jwks_url when prefetch succeeds" do
      port = start_test_server(:jwks_cache_opts_ok)
      url = "http://127.0.0.1:#{port}/jwks.json"
      Application.put_env(:whispr_notification, :jwt, jwks_url: url, refresh_interval_ms: 1)

      opts = App.jwks_cache_opts()
      assert Keyword.get(opts, :inline_jwks) =~ ~s|"keys"|
      assert Keyword.get(opts, :jwks_url) == url
      assert Keyword.get(opts, :refresh_interval_ms) == 1
    end
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, val), do: Application.put_env(:whispr_notification, key, val)
end
