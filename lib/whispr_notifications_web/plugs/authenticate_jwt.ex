defmodule WhisprNotificationsWeb.Plugs.AuthenticateJwt do
  @moduledoc """
  Validates Bearer JWT and enriches request context with claims.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias WhisprNotifications.Auth.JwtVerifier

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, claims} <- JwtVerifier.verify(token) do
      conn
      |> assign(:jwt_claims, claims)
      |> maybe_put_user_header(claims)
    else
      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
        |> halt()
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_authorization}
    end
  end

  defp maybe_put_user_header(conn, %{"sub" => sub}) when is_binary(sub) and sub != "" do
    if get_req_header(conn, "x-user-id") == [] do
      put_req_header(conn, "x-user-id", sub)
    else
      conn
    end
  end

  defp maybe_put_user_header(conn, _), do: conn
end
