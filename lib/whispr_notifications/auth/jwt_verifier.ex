defmodule WhisprNotifications.Auth.JwtVerifier do
  @moduledoc """
  Verifies JWT signatures using JWKS keys resolved by `kid`.
  """

  alias WhisprNotifications.Auth.JwksCache

  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(token) when is_binary(token) do
    with {:ok, header} <- decode_header(token),
         {:ok, kid} <- fetch_kid(header),
         {:ok, jwk} <- JwksCache.get_key(kid, jwks_cache_server()),
         {:ok, claims} <- verify_signature(token, jwk),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    end
  end

  def verify(_), do: {:error, :invalid_token}

  defp decode_header(token) do
    case String.split(token, ".") do
      [header_b64, _payload, _sig] ->
        with {:ok, raw} <- url_base64_decode(header_b64),
             {:ok, header} <- Jason.decode(raw) do
          {:ok, header}
        else
          _ -> {:error, :invalid_header}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp fetch_kid(%{"kid" => kid}) when is_binary(kid) and kid != "", do: {:ok, kid}
  defp fetch_kid(_), do: {:error, :missing_kid}

  defp verify_signature(token, jwk) do
    case JOSE.JWT.verify_strict(jwk, allowed_algs(), token) do
      {true, %JOSE.JWT{fields: claims}, _} when is_map(claims) -> {:ok, claims}
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_claims(claims) when is_map(claims) do
    with :ok <- validate_exp(claims),
         :ok <- validate_iss(claims),
         :ok <- validate_aud(claims) do
      :ok
    end
  end

  defp validate_exp(%{"exp" => exp}) when is_integer(exp) do
    if exp > System.system_time(:second), do: :ok, else: {:error, :token_expired}
  end

  defp validate_exp(_), do: {:error, :missing_exp}

  defp validate_iss(claims) do
    expected = jwt_config(:issuer)

    if is_nil(expected) or expected == "" do
      :ok
    else
      if claims["iss"] == expected, do: :ok, else: {:error, :invalid_issuer}
    end
  end

  defp validate_aud(claims) do
    expected = jwt_config(:audience)

    if is_nil(expected) or expected == "" do
      :ok
    else
      cond do
        claims["aud"] == expected -> :ok
        is_list(claims["aud"]) and expected in claims["aud"] -> :ok
        true -> {:error, :invalid_audience}
      end
    end
  end

  defp jwt_config(key) do
    Application.get_env(:whispr_notification, :jwt, [])
    |> Keyword.get(key)
  end

  defp jwks_cache_server do
    Application.get_env(:whispr_notification, :jwt, [])
    |> Keyword.get(:jwks_cache_server, WhisprNotifications.Auth.JwksCache)
  end

  defp allowed_algs do
    Application.get_env(:whispr_notification, :jwt, [])
    |> Keyword.get(:allowed_algs, ["ES256"])
  end

  defp url_base64_decode(value) do
    padded =
      case rem(byte_size(value), 4) do
        2 -> value <> "=="
        3 -> value <> "="
        _ -> value
      end

    Base.url_decode64(padded, padding: false)
  end
end
