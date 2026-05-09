defmodule WhisprNotificationsWeb.HealthControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias WhisprNotificationsWeb.Router

  # checker fakes : on injecte via Application.put_env pour simuler
  # Postgres / Redis up ou down sans toucher la vraie infra
  defmodule AllOkChecker do
    def check_postgres, do: :ok
    def check_redis, do: :ok
  end

  defmodule PgDownChecker do
    def check_postgres, do: {:error, "postgres_down"}
    def check_redis, do: :ok
  end

  defmodule RedisDownChecker do
    def check_postgres, do: :ok
    def check_redis, do: {:error, "redis_down"}
  end

  setup do
    previous = Application.get_env(:whispr_notification, :health_checker)
    on_exit(fn -> Application.put_env(:whispr_notification, :health_checker, previous) end)
    :ok
  end

  test "GET /api/v1/health returns 200" do
    conn =
      :get
      |> conn("/api/v1/health")
      |> Router.call([])

    assert conn.status == 200
  end

  test "GET /api/v1/health/ready returns 200 when all deps ok" do
    Application.put_env(:whispr_notification, :health_checker, AllOkChecker)

    conn =
      :get
      |> conn("/api/v1/health/ready")
      |> Router.call([])

    assert conn.status == 200
    assert conn.resp_body =~ "ready"
  end

  test "GET /api/v1/health/ready returns 503 when postgres down" do
    Application.put_env(:whispr_notification, :health_checker, PgDownChecker)

    conn =
      :get
      |> conn("/api/v1/health/ready")
      |> Router.call([])

    assert conn.status == 503
    assert conn.resp_body =~ "postgres_down"
  end

  test "GET /api/v1/health/ready returns 503 when redis down" do
    Application.put_env(:whispr_notification, :health_checker, RedisDownChecker)

    conn =
      :get
      |> conn("/api/v1/health/ready")
      |> Router.call([])

    assert conn.status == 503
    assert conn.resp_body =~ "redis_down"
  end
end
