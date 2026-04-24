defmodule WhisprNotifications.Delivery.FcmClientTest do
  use ExUnit.Case, async: false

  alias WhisprNotifications.Delivery.FcmClient

  setup do
    # FCM configuré pour ce suite : project id réel + un `goth_fetch`
    # stub qui renvoie un access token prédictible.
    previous_fcm = Application.get_env(:whispr_notification, :fcm)

    Application.put_env(:whispr_notification, :fcm,
      project_id: "test-project",
      credentials: %{},
      enabled: true
    )

    previous_goth = Application.get_env(:whispr_notification, :fcm_goth_fetch)

    Application.put_env(
      :whispr_notification,
      :fcm_goth_fetch,
      fn _name -> {:ok, %{token: "test-access-token"}} end
    )

    previous_req = Application.get_env(:whispr_notification, :fcm_req_post)

    on_exit(fn ->
      restore(:fcm, previous_fcm)
      restore(:fcm_goth_fetch, previous_goth)
      restore(:fcm_req_post, previous_req)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:whispr_notification, key)
  defp restore(key, value), do: Application.put_env(:whispr_notification, key, value)

  defp stub_post(fun), do: Application.put_env(:whispr_notification, :fcm_req_post, fun)

  describe "send/2 — happy path" do
    test "returns :ok when FCM replies 200" do
      parent = self()

      stub_post(fn url, opts ->
        send(parent, {:fcm_call, url, opts})
        {:ok, %Req.Response{status: 200, body: %{"name" => "projects/x/messages/abc"}}}
      end)

      device = %{token: "android-token", platform: :android, app: nil}
      payload = %{title: "Hi", body: "world", data: %{"cid" => "conv-1"}}

      assert :ok = FcmClient.send(device, payload)

      assert_receive {:fcm_call, url, opts}
      assert url == "https://fcm.googleapis.com/v1/projects/test-project/messages:send"
      assert {"authorization", "Bearer test-access-token"} in Keyword.fetch!(opts, :headers)

      body = Keyword.fetch!(opts, :json)
      assert body["message"]["token"] == "android-token"
      assert body["message"]["notification"] == %{"title" => "Hi", "body" => "world"}
      assert body["message"]["data"] == %{"cid" => "conv-1"}
      assert body["message"]["android"] == %{"priority" => "HIGH"}
      refute Map.has_key?(body["message"], "apns")
    end

    test "omits the data block when the payload has no data" do
      stub_post(fn _url, opts ->
        send(self(), :ok)
        assert Keyword.fetch!(opts, :json)["message"] |> Map.has_key?("data") == false
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      device = %{token: "t", platform: :android, app: nil}
      assert :ok = FcmClient.send(device, %{title: "t", body: "b"})
    end
  end

  describe "send/2 — invalid token" do
    for code <- ["UNREGISTERED", "NOT_FOUND", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"] do
      test "maps errorCode=#{code} to {:error, :token_invalid}" do
        code = unquote(code)

        stub_post(fn _url, _opts ->
          {:ok,
           %Req.Response{
             status: 404,
             body: %{"error" => %{"details" => [%{"errorCode" => code}]}}
           }}
        end)

        device = %{token: "dead-token", platform: :android, app: nil}
        assert {:error, :token_invalid} = FcmClient.send(device, %{title: "t", body: "b"})
      end
    end

    test "4xx with unknown errorCode falls back to :token_invalid" do
      stub_post(fn _url, _opts ->
        {:ok, %Req.Response{status: 400, body: %{"error" => %{"status" => "QUOTA_EXCEEDED"}}}}
      end)

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :token_invalid} = FcmClient.send(device, %{title: "t", body: "b"})
    end
  end

  describe "send/2 — transient failures" do
    test "HTTP 500 returns {:error, :transient}" do
      stub_post(fn _url, _opts -> {:ok, %Req.Response{status: 500, body: "upstream"}} end)
      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :transient} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "network error returns {:error, :transient}" do
      stub_post(fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end)
      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :transient} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "UNAUTHENTICATED is treated as :transient so we don't soft-delete valid tokens" do
      stub_post(fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => %{"status" => "UNAUTHENTICATED"}}}}
      end)

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :transient} = FcmClient.send(device, %{title: "t", body: "b"})
    end
  end

  describe "send/2 — configuration / input edge cases" do
    test "returns {:error, :not_configured} when project_id is missing" do
      Application.put_env(:whispr_notification, :fcm,
        project_id: nil,
        credentials: nil,
        enabled: false
      )

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :not_configured} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "returns {:error, :not_configured} when Goth worker is not running" do
      Application.put_env(
        :whispr_notification,
        :fcm_goth_fetch,
        fn _name -> exit({:noproc, {GenServer, :call, []}}) end
      )

      device = %{token: "t", platform: :android, app: nil}
      assert {:error, :not_configured} = FcmClient.send(device, %{title: "t", body: "b"})
    end

    test "returns {:error, :token_invalid} for empty / nil token inputs" do
      assert {:error, :token_invalid} =
               FcmClient.send(%{token: "", platform: :android, app: nil}, %{})

      assert {:error, :token_invalid} =
               FcmClient.send(%{token: nil, platform: :android, app: nil}, %{})
    end
  end
end
