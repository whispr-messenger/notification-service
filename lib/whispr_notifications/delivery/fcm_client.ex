defmodule WhisprNotifications.Delivery.FcmClient do
  @moduledoc """
  FCM HTTP v1 client.

  Authentification via un worker Goth (`WhisprNotifications.Goth`) qui
  charge le service-account JSON depuis `FCM_JSON_KEYFILE` / `FCM_JSON`.
  L'endpoint legacy `/fcm/send` (utilisé par `:fcmex` 0.6.x) a été
  décommissionné par Google en juin 2024, donc on tape directement le
  v1 `/v1/projects/{project_id}/messages:send` via `Req`.

  Mapping d'erreurs :

    * `UNREGISTERED`, `NOT_FOUND`, `INVALID_ARGUMENT`,
      `SENDER_ID_MISMATCH` → `{:error, :token_invalid}` — l'appelant
      doit soft-delete la ligne device.
    * HTTP 5xx, échec réseau, timeout → `{:error, :transient}` —
      l'appelant peut retry via `RetryManager`.
    * FCM non configuré (pas de creds dans l'env) → `{:error,
      :not_configured}` — cas dev local.
  """

  alias WhisprNotifications.Devices.DeviceCache
  require Logger

  @callback send(DeviceCache.device(), map()) ::
              :ok | {:error, :token_invalid | :transient | :not_configured | term()}

  @behaviour __MODULE__

  @fcm_v1_endpoint "https://fcm.googleapis.com/v1/projects/"
  @goth_name WhisprNotifications.Goth

  @impl true
  def send(%{token: token} = device, payload)
      when is_binary(token) and token != "" do
    with {:ok, project_id} <- fetch_project_id(),
         {:ok, access_token} <- fetch_access_token(),
         body <- build_body(device, payload),
         {:ok, response} <- post(project_id, access_token, body) do
      handle_response(response)
    end
  end

  def send(_device, _payload), do: {:error, :token_invalid}

  # ----- config ----------------------------------------------------------

  defp fetch_project_id do
    cfg = Application.get_env(:whispr_notification, :fcm, [])

    case Keyword.get(cfg, :project_id) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :not_configured}
    end
  end

  defp fetch_access_token do
    case goth_fetch().(@goth_name) do
      {:ok, %{token: token}} -> {:ok, token}
      {:ok, %{"access_token" => token}} -> {:ok, token}
      {:error, reason} -> {:error, {:oauth_error, reason}}
    end
  rescue
    # Goth worker non démarré (FCM désactivé dans cet env).
    ArgumentError -> {:error, :not_configured}
    e -> {:error, {:oauth_error, e}}
  catch
    :exit, _ -> {:error, :not_configured}
  end

  # ----- payload ---------------------------------------------------------

  defp build_body(%{token: token, platform: platform}, payload) do
    message =
      %{
        "token" => to_string(token),
        "notification" => notification_part(payload),
        "data" => data_part(payload),
        "android" => android_part(platform, payload),
        "apns" => apns_part(platform)
      }
      |> drop_nil()

    %{"message" => message}
  end

  # Accepts both a flat shape (`%{title, body, data}`) and the
  # `Formatter.to_platform_payload/3` shape
  # (`%{notification: %{title, body}, data: ...}`). The latter is what
  # BatchProcessor actually passes in.
  defp notification_part(payload) do
    nested = Map.get(payload, :notification) || %{}

    %{
      "title" => to_string(Map.get(payload, :title) || Map.get(nested, :title, "")),
      "body" => to_string(Map.get(payload, :body) || Map.get(nested, :body, ""))
    }
  end

  defp data_part(payload) do
    case Map.get(payload, :data) do
      map when is_map(map) and map_size(map) > 0 ->
        Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)

      _ ->
        nil
    end
  end

  defp android_part(:android, _payload), do: %{"priority" => "HIGH"}
  defp android_part(_, _), do: nil

  # APNS reste géré par `ApnsClient` via Pigeon ; ce module ne doit
  # jamais viser un token iOS même si un device passe avec
  # `platform: :ios`.
  defp apns_part(_), do: nil

  defp drop_nil(map) do
    Enum.reduce(map, %{}, fn
      {_k, nil}, acc -> acc
      {k, v}, acc -> Map.put(acc, k, v)
    end)
  end

  # ----- HTTP ------------------------------------------------------------

  defp post(project_id, access_token, body) do
    url = @fcm_v1_endpoint <> project_id <> "/messages:send"

    opts =
      Application.get_env(:whispr_notification, :fcm_req_options, [])
      |> Keyword.put_new(:receive_timeout, 10_000)
      |> Keyword.put_new(:retry, false)

    request_fn = Application.get_env(:whispr_notification, :fcm_req_post, &Req.post/2)

    full_opts =
      [json: body, headers: [{"authorization", "Bearer " <> access_token}]] ++ opts

    try do
      request_fn.(url, full_opts)
    rescue
      e ->
        Logger.warning("[FcmClient] request crashed: #{inspect(e)}")
        {:error, :crashed}
    end
    |> case do
      {:ok, %Req.Response{} = resp} ->
        {:ok, resp}

      {:ok, %{status: _} = resp} ->
        {:ok, resp}

      {:error, reason} ->
        Logger.warning("[FcmClient] transient error #{inspect(reason)}")
        {:error, :transient}
    end
  end

  # ----- response --------------------------------------------------------

  defp handle_response(%{status: status}) when status in 200..299, do: :ok

  defp handle_response(%{status: status, body: body}) when status in 400..499 do
    case fcm_error_code(body) do
      code when code in ["UNREGISTERED", "NOT_FOUND", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"] ->
        {:error, :token_invalid}

      "UNAUTHENTICATED" ->
        Logger.error("[FcmClient] FCM rejected OAuth token (UNAUTHENTICATED)")
        {:error, :transient}

      other ->
        Logger.warning("[FcmClient] 4xx status=#{status} errorCode=#{inspect(other)}")
        {:error, :token_invalid}
    end
  end

  defp handle_response(%{status: status}) when status in 500..599 do
    Logger.warning("[FcmClient] FCM 5xx status=#{status}")
    {:error, :transient}
  end

  defp handle_response(other) do
    Logger.warning("[FcmClient] unexpected response #{inspect(other)}")
    {:error, :transient}
  end

  defp fcm_error_code(body) when is_map(body) do
    case get_in(body, ["error", "details"]) do
      details when is_list(details) ->
        Enum.find_value(details, fn d -> Map.get(d, "errorCode") end)

      _ ->
        get_in(body, ["error", "status"])
    end || "UNKNOWN"
  end

  defp fcm_error_code(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> fcm_error_code(decoded)
      _ -> "UNKNOWN"
    end
  end

  defp fcm_error_code(_), do: "UNKNOWN"

  # ----- DI hook pour les tests -----------------------------------------

  defp goth_fetch do
    Application.get_env(:whispr_notification, :fcm_goth_fetch, &Goth.fetch/1)
  end
end
