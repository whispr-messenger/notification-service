defmodule WhisprNotificationsWeb.Plugs.Authenticate do
  @moduledoc false
  import Plug.Conn

  @behaviour Plug

  alias WhisprNotifications.Auth.JwtVerifier

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- JwtVerifier.verify(token) do
      conn
      |> assign(:jwt_claims, claims)
      |> assign(:jwt_sub, Map.get(claims, "sub"))
    else
      _ -> unauthorized(conn)
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
