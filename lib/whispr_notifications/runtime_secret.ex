defmodule WhisprNotifications.RuntimeSecret do
  @moduledoc """
  Garde-fous pour les secrets lus au démarrage du release dans `runtime.exs`.

  Phoenix utilise `secret_key_base` pour signer/chiffrer les cookies de session
  et les tokens. Une valeur trop courte affaiblit ces garanties — `mix phx.gen.secret`
  produit 64 octets et c'est le minimum recommandé en prod.
  """

  @minimum_secret_key_base_bytes 64

  @doc """
  Vérifie qu'une valeur de `SECRET_KEY_BASE` est utilisable en prod.

  Renvoie la valeur telle quelle si elle est conforme, raise sinon.
  Ne pas appeler en `:dev` ou `:test` : on tolère un secret court pour ne pas
  ralentir le boot local.
  """
  @spec validate_secret_key_base!(String.t()) :: String.t()
  def validate_secret_key_base!(value) when is_binary(value) do
    if byte_size(value) < @minimum_secret_key_base_bytes do
      raise """
      SECRET_KEY_BASE must be at least #{@minimum_secret_key_base_bytes} bytes \
      (currently #{byte_size(value)}).
      Generate one with: mix phx.gen.secret
      """
    end

    value
  end

  @doc "Longueur minimale exigée en bytes pour `SECRET_KEY_BASE` en prod."
  @spec minimum_secret_key_base_bytes() :: pos_integer()
  def minimum_secret_key_base_bytes, do: @minimum_secret_key_base_bytes
end
