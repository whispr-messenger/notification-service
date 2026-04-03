defmodule WhisprNotifications.Auth.JwtVerifier do
  @moduledoc false

  alias WhisprNotifications.Auth.JwksCache

  @spec verify(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(token) when is_binary(token) do
    jwt_config = Application.get_env(:whispr_notification, :jwt) || []
    server = Keyword.get(jwt_config, :jwks_cache_server, WhisprNotifications.Auth.JwksCache)
    allowed = Keyword.get(jwt_config, :allowed_algs, ["ES256"])
    issuer = Keyword.get(jwt_config, :issuer)
    audience = Keyword.get(jwt_config, :audience)

    with {:ok, %{"kid" => kid, "alg" => alg}} <- decode_protected_header(token),
         true <- alg in allowed,
         {:ok, jwk} <- JwksCache.get_key(kid, server),
         {:ok, claims} <- verify_signature(token, jwk, allowed),
         :ok <- validate_exp(claims),
         :ok <- validate_iss_aud(claims, issuer, audience) do
      {:ok, stringify_claims(claims)}
    else
      false -> {:error, :unsupported_alg}
      {:error, other} -> {:error, other}
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

  defp verify_signature(token, jwk, allowed) do
    case JOSE.JWT.verify_strict(jwk, allowed, token) do
      {true, jwt, _jws} ->
        {_modules, claims} = JOSE.JWT.to_map(jwt)
        {:ok, claims}

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

  defp validate_iss_aud(claims, issuer, audience) do
    cond do
      issuer && claim_str(claims, "iss") != issuer ->
        {:error, :invalid_issuer}

      audience && claim_str(claims, "aud") != audience ->
        {:error, :invalid_audience}

      true ->
        :ok
    end
  end

  defp claim_int(claims, key) do
    Map.get(claims, key) ||
      Map.get(claims, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(claims, key)
  end

  defp claim_str(claims, key) do
    case Map.get(claims, key) do
      nil -> Map.get(claims, String.to_atom(key))
      v -> v
    end
  end

  defp stringify_claims(claims) when is_map(claims) do
    Map.new(claims, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end
end
