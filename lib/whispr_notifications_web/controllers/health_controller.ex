defmodule WhisprNotificationsWeb.HealthController do
  use WhisprNotificationsWeb, :controller

  alias Ecto.Adapters.SQL
  alias WhisprNotifications.RedisConfig
  alias WhisprNotifications.Repo

  # liveness : process-only, repond toujours 200 si le BEAM repond
  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  # readiness : 503 si Postgres ou Redis sont down, k8s drain le pod
  def ready(conn, _params) do
    case check_dependencies() do
      :ok ->
        conn |> put_status(200) |> json(%{status: "ready"})

      {:error, reason} ->
        conn |> put_status(503) |> json(%{status: "not_ready", reason: reason})
    end
  end

  defp check_dependencies do
    checker = Application.get_env(:whispr_notification, :health_checker, __MODULE__)

    with :ok <- checker.check_postgres() do
      checker.check_redis()
    end
  end

  @doc false
  def check_postgres do
    case SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "postgres_down"}
    end
  rescue
    _ -> {:error, "postgres_down"}
  end

  @doc false
  def check_redis do
    case Redix.start_link(RedisConfig.build()) do
      {:ok, conn} ->
        result = Redix.command(conn, ["PING"], timeout: 2_000)
        Redix.stop(conn)

        case result do
          {:ok, "PONG"} -> :ok
          _ -> {:error, "redis_down"}
        end

      _ ->
        {:error, "redis_down"}
    end
  rescue
    _ -> {:error, "redis_down"}
  end
end
