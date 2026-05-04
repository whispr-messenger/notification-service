defmodule WhisprNotifications.Delivery.ApnsClient do
  @moduledoc """
  APNS push via Pigeon 2.x (HTTP/2 + JWT ES256).

  Same callback contract as the previous stub so `BatchProcessor` and
  `Devices.mark_invalid/2` don't need to change:

      :ok
      | {:error, :token_invalid}     # hard failure — soft-delete the device
      | {:error, :transient}         # retryable (network, 5xx, quota, auth)
      | {:error, :not_configured}    # APNS creds absent in this env (dev/CI)

  Response atoms from `Pigeon.APNS` are mapped as follows:

    * `:success`                                          → `:ok`
    * `:bad_device_token`, `:unregistered`,
      `:device_token_not_for_topic`, `:missing_device_token`,
      `:expired_token`, `:bad_topic`, `:topic_disallowed`,
      `:invalid_push_type`                                → `{:error, :token_invalid}`
    * `:internal_server_error`, `:service_unavailable`,
      `:too_many_requests`, `:too_many_provider_token_updates`,
      `:expired_provider_token`, `:invalid_provider_token`,
      `:missing_provider_token`, `:idle_timeout`,
      `:shutdown`, `:unknown_error`, `:timeout`           → `{:error, :transient}`

  Everything unknown degrades to `:transient` so we never drop a valid token
  on an error we didn't anticipate.
  """

  alias Pigeon.APNS.Notification, as: APNSNotification
  alias WhisprNotifications.Delivery.ApnsDispatcher
  alias WhisprNotifications.Devices.DeviceCache

  require Logger

  @callback send(DeviceCache.device(), map()) ::
              :ok | {:error, :token_invalid | :transient | :not_configured | term()}

  @behaviour __MODULE__

  @invalid_token_responses [
    :bad_device_token,
    :unregistered,
    :device_token_not_for_topic,
    :missing_device_token,
    :expired_token,
    :bad_topic,
    :topic_disallowed,
    :invalid_push_type
  ]

  @impl true
  @spec send(DeviceCache.device(), map()) ::
          :ok | {:error, :token_invalid | :transient | :not_configured | term()}
  def send(%{token: token} = device, payload)
      when is_binary(token) and token != "" do
    cond do
      not apns_enabled?() -> {:error, :not_configured}
      not dispatcher_running?() -> {:error, :not_configured}
      true -> do_push(device, payload)
    end
  end

  def send(_device, _payload), do: {:error, :token_invalid}

  @doc """
  Builds a `Pigeon.APNS.Notification` from the internal payload shape used by
  `BatchProcessor` + `Formatter.to_platform_payload/3`. Public so it can be
  unit-tested without standing up a dispatcher.
  """
  @spec build_notification(DeviceCache.device(), map()) :: APNSNotification.t()
  def build_notification(%{token: token} = device, payload) do
    topic = topic_for(device)

    %APNSNotification{
      device_token: token,
      topic: topic,
      push_type: "alert",
      payload: normalise_payload(payload)
    }
  end

  @doc """
  Pure mapping from a Pigeon APNS response atom back to the internal
  `ApnsClient` contract. Public for unit-testing.
  """
  @spec response_to_result(APNSNotification.t()) ::
          :ok | {:error, :token_invalid | :transient}
  def response_to_result(%APNSNotification{response: :success}), do: :ok

  def response_to_result(%APNSNotification{response: resp})
      when resp in @invalid_token_responses do
    {:error, :token_invalid}
  end

  def response_to_result(%APNSNotification{response: resp}) do
    Logger.warning("[ApnsClient] transient APNS response: #{inspect(resp)}")
    {:error, :transient}
  end

  # ----- private ---------------------------------------------------------

  defp apns_enabled? do
    :whispr_notification
    |> Application.get_env(:apns, [])
    |> Keyword.get(:enabled, false) == true
  end

  defp dispatcher_running? do
    dispatcher_module() |> Process.whereis() != nil
  end

  defp dispatcher_module do
    Application.get_env(:whispr_notification, :apns_dispatcher, ApnsDispatcher)
  end

  defp do_push(device, payload) do
    notification = build_notification(device, payload)
    dispatcher = dispatcher_module()
    masked = masked_token(device)

    case dispatcher.push(notification) |> response_to_result() do
      :ok ->
        Logger.info("APNS push succeeded for #{masked}")
        :ok

      {:error, reason} = err ->
        Logger.error("APNS push failed for #{masked}: #{inspect(reason)}")
        err
    end
  rescue
    e ->
      Logger.warning("[ApnsClient] Pigeon push raised: #{inspect(e)}")
      {:error, :transient}
  catch
    :exit, _ -> {:error, :not_configured}
  end

  # APNS topic = app bundle id. Falls back to a configured default if the
  # device row didn't carry one (older inserts before the column existed).
  defp topic_for(%{app: app}) when is_binary(app) and app != "", do: app

  defp topic_for(_device) do
    :whispr_notification
    |> Application.get_env(:apns, [])
    |> Keyword.get(:default_topic)
  end

  # Accepts both the `Formatter.to_platform_payload/3` shape (already
  # `%{"aps" => %{...}, "meta" => %{...}}`) and a flat `%{title, body}`
  # convenience shape used by some callers/tests.
  defp normalise_payload(%{"aps" => _} = payload), do: payload

  defp normalise_payload(%{title: title, body: body} = payload) do
    base = %{
      "aps" => %{
        "alert" => %{
          "title" => to_string(title),
          "body" => to_string(body)
        },
        "sound" => "default"
      }
    }

    case Map.get(payload, :data) do
      map when is_map(map) and map_size(map) > 0 ->
        Map.put(base, "meta", Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end))

      _ ->
        base
    end
  end

  defp normalise_payload(payload) when is_map(payload), do: payload

  defp masked_token(device) do
    case token(device) do
      "unknown" ->
        "unknown"

      t when is_binary(t) ->
        suffix_length = min(String.length(t), 6)
        "***" <> String.slice(t, -suffix_length, suffix_length)
    end
  end

  defp token(%{token: t}) when is_binary(t), do: t
  defp token(_), do: "unknown"
end
