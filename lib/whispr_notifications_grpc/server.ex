defmodule WhisprNotificationsGrpc.Server do
  @moduledoc """
  gRPC server configuration for the notification service.
  Listens on the configured gRPC port (default: 40011).
  """

  require Logger

  def child_spec(_opts) do
    port = Application.get_env(:whispr_notification, :grpc_port, 40011)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [port]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(port) do
    Logger.info("gRPC server starting on port #{port}")

    # grpcbox server configuration
    # Services are registered via the grpcbox application config
    :grpcbox.start_server(%{
      grpc_opts: %{
        service_protos: [],
        unary_interceptor: nil,
        stream_interceptor: nil
      },
      listen_opts: %{
        port: port
      }
    })
  rescue
    e ->
      Logger.warning("gRPC server failed to start: #{inspect(e)}, continuing without gRPC")
      :ignore
  end
end
