defmodule WhisprNotifications.Auth.Jwks do
  @moduledoc false

  @doc """
  Parses a JWKS JSON document into a map of `kid => %JOSE.JWK{}` (public keys only).
  Only EC P-256 (`crv` P-256) keys with a `kid` are loaded.
  """
  @spec keys_from_json(String.t()) :: {:ok, %{optional(String.t()) => JOSE.JWK.t()}} | {:error, term()}
  def keys_from_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"keys" => keys}} when is_list(keys) -> build_key_map(keys)
      {:ok, _} -> {:error, :invalid_jwks_shape}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp build_key_map(keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case normalize_jwk_entry(key) do
        {:ok, kid, jwk} -> {:cont, {:ok, Map.put(acc, kid, jwk)}}
        :skip -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_jwk_entry(%{"kid" => kid, "kty" => "EC", "crv" => "P-256"} = key)
       when is_binary(kid) do
    try do
      jwk = JOSE.JWK.from(key)
      jwk_public = JOSE.JWK.to_public(jwk)
      {:ok, kid, jwk_public}
    rescue
      _ -> {:error, :bad_jwk}
    end
  end

  defp normalize_jwk_entry(%{"kid" => _}), do: :skip
  defp normalize_jwk_entry(_), do: :skip

  @doc """
  Fetches JWKS from `url` (HTTP GET). Returns the same map shape as `keys_from_json/1`.
  """
  @spec fetch_keys(String.t()) :: {:ok, %{optional(String.t()) => JOSE.JWK.t()}} | {:error, term()}
  def fetch_keys(url) when is_binary(url) do
    case Req.get(url,
           receive_timeout: 15_000,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: 200, body: body}} ->
        body_json = if is_binary(body), do: body, else: Jason.encode!(body)
        keys_from_json(body_json)

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
