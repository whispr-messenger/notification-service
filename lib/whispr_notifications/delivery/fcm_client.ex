defmodule WhisprNotifications.Delivery.FcmClient do
  @moduledoc """
  FCM (Firebase Cloud Messaging) client for sending push notifications
  to both Android and iOS devices via the FCM v1 HTTP API.
  """

  require Logger

  alias WhisprNotifications.Devices.DeviceCache

  @callback send(DeviceCache.device(), map()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @fcm_v1_url "https://fcm.googleapis.com/v1/projects/%s/messages:send"

  @impl true
  def send(device, payload) do
    with {:ok, project_id} <- fetch_project_id(),
         {:ok, token} <- fetch_token(device) do
      send_via_fcm(token, to_string(device.platform), payload, project_id)
    else
      {:error, reason} ->
        Logger.warning("FCM push skipped: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a push notification to a specific device token via FCM v1 API.
  Used for both Android and iOS devices registered with FCM.
  """
  def send_to_token(token, title, body, data \\ %{}) do
    with {:ok, project_id} <- fetch_project_id(),
         {:ok, token} <- fetch_token(%{token: token}) do
      message = %{
        "message" => %{
          "token" => token,
          "notification" => %{
            "title" => title,
            "body" => body
          },
          "data" => stringify_data(data)
        }
      }

      post_to_fcm(message, project_id)
    else
      {:error, reason} ->
        Logger.warning("FCM send_to_token skipped: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a notification using platform-specific configuration.
  Applies Android or APNS-specific options depending on the device platform.
  """
  def send_platform_message(token, platform, title, body, data \\ %{}) do
    with {:ok, project_id} <- fetch_project_id(),
         {:ok, token} <- fetch_token(%{token: token}) do
      base_message = %{
        "token" => token,
        "notification" => %{
          "title" => title,
          "body" => body
        },
        "data" => stringify_data(data)
      }

      message =
        case platform do
          "android" ->
            Map.put(base_message, "android", %{
              "priority" => "high",
              "notification" => %{
                "channel_id" => "whispr_messages",
                "sound" => "default"
              }
            })

          "ios" ->
            Map.put(base_message, "apns", %{
              "payload" => %{
                "aps" => %{
                  "sound" => "default",
                  "badge" => 1
                }
              }
            })

          _ ->
            base_message
        end

      post_to_fcm(%{"message" => message}, project_id)
    else
      {:error, reason} ->
        Logger.warning("FCM send_platform_message skipped: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_via_fcm(token, platform, payload, _project_id) do
    title = get_in(payload, [:notification, :title]) ||
            get_in(payload, ["aps", "alert", "title"]) ||
            "Whispr"

    body = get_in(payload, [:notification, :body]) ||
           get_in(payload, ["aps", "alert", "body"]) ||
           ""

    data = Map.get(payload, :data, %{}) |> stringify_data()

    send_platform_message(token, platform, title, body, data)
  end

  defp fetch_project_id do
    project_id = Application.get_env(:fcmex, :project_id)

    if is_binary(project_id) and project_id != "" do
      {:ok, project_id}
    else
      {:error, :fcm_not_configured}
    end
  end

  defp fetch_token(%{token: token}) when is_binary(token) and token != "", do: {:ok, token}
  defp fetch_token(_), do: {:error, :invalid_device_token}

  defp post_to_fcm(message, project_id) do
    url = :io_lib.format(@fcm_v1_url, [project_id]) |> IO.iodata_to_binary()

    case get_access_token() do
      {:ok, access_token} ->
        headers = [
          {"authorization", "Bearer #{access_token}"},
          {"content-type", "application/json"}
        ]

        body = Jason.encode!(message)

        case Req.post(url, body: body, headers: headers) do
          {:ok, %{status: status}} when status in 200..299 ->
            Logger.info("FCM push sent successfully")
            :ok

          {:ok, %{status: 404}} ->
            Logger.warning("FCM token not found (unregistered device)")
            {:error, :token_not_registered}

          {:ok, %{status: status, body: resp_body}} ->
            Logger.error("FCM push failed with status #{status}: #{inspect(resp_body)}")
            {:error, {:fcm_error, status}}

          {:error, reason} ->
            Logger.error("FCM push request failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to get FCM access token: #{inspect(reason)}")
        {:error, :auth_failed}
    end
  end

  defp get_access_token do
    keyfile_path = Application.get_env(:fcmex, :json_keyfile)

    if is_nil(keyfile_path) or not File.exists?(to_string(keyfile_path)) do
      Logger.warning("FCM JSON keyfile not found at #{inspect(keyfile_path)}")
      {:error, :keyfile_not_found}
    else
      case File.read(keyfile_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, %{"type" => "service_account"} = credentials} ->
              generate_jwt_token(credentials)

            _ ->
              {:error, :invalid_keyfile}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp generate_jwt_token(credentials) do
    now = System.system_time(:second)
    scope = "https://www.googleapis.com/auth/firebase.messaging"

    header = Base.url_encode64(Jason.encode!(%{"alg" => "RS256", "typ" => "JWT"}), padding: false)

    claims =
      Base.url_encode64(
        Jason.encode!(%{
          "iss" => credentials["client_email"],
          "scope" => scope,
          "aud" => "https://oauth2.googleapis.com/token",
          "iat" => now,
          "exp" => now + 3600
        }),
        padding: false
      )

    signing_input = "#{header}.#{claims}"

    case sign_rs256(signing_input, credentials["private_key"]) do
      {:ok, signature} ->
        jwt = "#{signing_input}.#{Base.url_encode64(signature, padding: false)}"
        exchange_jwt_for_token(jwt)

      {:error, _} = error ->
        error
    end
  end

  defp sign_rs256(input, pem_key) do
    try do
      [entry | _] = :public_key.pem_decode(pem_key)
      key = :public_key.pem_entry_decode(entry)
      signature = :public_key.sign(input, :sha256, key)
      {:ok, signature}
    rescue
      e -> {:error, e}
    end
  end

  defp exchange_jwt_for_token(jwt) do
    url = "https://oauth2.googleapis.com/token"
    body = URI.encode_query(%{
      "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
      "assertion" => jwt
    })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{body: resp}} ->
        {:error, {:token_exchange_failed, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stringify_data(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_data(_), do: %{}
end
