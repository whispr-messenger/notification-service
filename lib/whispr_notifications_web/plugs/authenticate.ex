defmodule WhisprNotificationsWeb.Plugs.Authenticate do
  @moduledoc false
  import Plug.Conn

  @behaviour Plug

  @allowed_algs ["ES256"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{"kid" => kid, "alg" => alg}} <- decode_protected_header(token),
         true <- alg in @allowed_algs,
         {:ok, jwk} <- WhisprNotifications.Auth.JwksCache.get_key(kid),
         {:ok, claims} <- verify_and_validate(token, jwk) do
      conn
      |> assign(:jwt_claims, claims)
      |> assign(:jwt_sub, claim_string(claims, "sub"))
    else
      {:error, _} -> unauthorized(conn)
      :error -> unauthorized(conn)
      false -> unauthorized(conn)
      _ -> unauthorized(conn)
    end
  end

  defp decode_protected_header(token) do
    with [b64 | _] <- String.split(token, "."),
         {:ok, json} <- url_b64_decode(b64),
         {:ok, map} <- Jason.decode(json) do
      {:ok, map}
    else
      _ -> {:error, :invalid_header}
    end
  end

  defp url_b64_decode(b64) do
    padded = pad_base64url(b64)

    case Base.url_decode64(padded, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> :error
    end
  end

  defp pad_base64url(b64) do
    case rem(byte_size(b64), 4) do
      0 -> b64
      r -> b64 <> String.duplicate("=", 4 - r)
    end
  end

  defp verify_and_validate(token, jwk) do
    case JOSE.JWT.verify_strict(jwk, @allowed_algs, token) do
      {true, jwt, _jws} ->
        {_modules, claims} = JOSE.JWT.to_map(jwt)

        case validate_exp(claims) do
          :ok -> {:ok, claims}
          {:error, _} = e -> e
        end

      _ ->
        {:error, :invalid_signature}
    end
  end

  defp validate_exp(claims) do
    case claim_int(claims, "exp") do
      exp when is_integer(exp) ->
        if exp >= System.system_time(:second), do: :ok, else: {:error, :expired}

      _ ->
        :ok
    end
  end

  defp claim_int(claims, key) do
    bkey = String.to_existing_atom(key)

    Map.get(claims, key) ||
      Map.get(claims, bkey) ||
      Map.get(claims, String.to_atom(key))
  rescue
    ArgumentError -> Map.get(claims, key)
  end

  defp claim_string(claims, key) do
    case Map.get(claims, key) do
      nil -> Map.get(claims, String.to_atom(key))
      v -> v
    end
  end

  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
