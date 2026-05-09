defmodule WhisprNotificationsWeb.Endpoint do
  @moduledoc """
  Phoenix Endpoint pour notification-service.

  Le check WebSocket d'origine (WHISPR-1353) est cable via `check_origin`
  meme si aucun socket n'est encore monte ici. Ca evite qu'un futur ajout
  de socket (LiveView, push direct) reactive accidentellement le wildcard
  permissif et expose l'API a des connexions cross-origin non autorisees.
  """

  use Phoenix.Endpoint, otp_app: :whispr_notification

  # Si tu veux du WebSocket plus tard (LiveView, etc.), tu l'ajouteras ici.

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:whispr_notification, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head

  plug WhisprNotificationsWeb.Plugs.Cors

  plug WhisprNotificationsWeb.Router

  @doc """
  WebSocket origin check (WHISPR-1353).

  Phoenix appelle ce MFA par connexion avec l'`%URI{}` de la requete.

  - En `:prod`, seules les origines listees dans `CORS_ALLOWED_ORIGINS`
    (separateur virgule) sont acceptees. Une valeur absente, vide ou
    `*` fait crasher : on refuse de booter un transport WS permissif
    en prod.
  - En `:dev` / `:test`, retourne `true` (permissif) pour ne pas casser
    le tooling local.
  """
  @spec ws_check_origin(URI.t()) :: boolean()
  def ws_check_origin(%URI{} = uri) do
    case Application.get_env(:whispr_notification, :env) do
      :prod ->
        prod_origin_allowed?(uri)

      _ ->
        true
    end
  end

  defp prod_origin_allowed?(%URI{} = uri) do
    case System.get_env("CORS_ALLOWED_ORIGINS") do
      nil ->
        raise "CORS_ALLOWED_ORIGINS must be set in production for WebSocket origin check (WHISPR-1353)"

      "" ->
        raise "CORS_ALLOWED_ORIGINS cannot be empty in production for WebSocket origin check (WHISPR-1353)"

      "*" ->
        raise "CORS_ALLOWED_ORIGINS=* is not allowed for WebSocket origin check in production (WHISPR-1353)"

      value ->
        origins =
          value
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        origin_string = build_origin_string(uri)
        origin_string in origins
    end
  end

  defp build_origin_string(%URI{scheme: scheme, host: host, port: port})
       when is_binary(scheme) and is_binary(host) do
    base = "#{scheme}://#{host}"

    cond do
      is_nil(port) -> base
      scheme == "https" and port == 443 -> base
      scheme == "http" and port == 80 -> base
      true -> "#{base}:#{port}"
    end
  end

  defp build_origin_string(_), do: ""
end
