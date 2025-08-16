defmodule Ambrosia.Application do
  @moduledoc """
  Ambrosia - The immortal Gemini server.
  Main application supervisor that ensures fault tolerance through
  supervision trees. The BEAM way <3
  """
  use Application
  require Logger
  
  @impl true
  def start(_type, _args) do
    Logger.info("🏛️ Gearing up to Serve the food of the gods...")
    
    # Get configuration
    config = load_config()
    
    # Define child processes
    children = [
      # Metrics supervisor
      {Ambrosia.Telemetry, []},
      # Rate limiter (ETS-based)
      {Ambrosia.RateLimiter, [max_requests: 10, window_ms: 1000]},
      # Connection manager
      {Ambrosia.ConnectionManager, config},
      # Ranch listener for TCP connections
      ranch_child_spec(config)
    ] ++ metrics_children()  # Add metrics endpoint if enabled
    
    # Supervision strategy:
    # - one_for_one: if a child dies, only restart that child
    # - max_restarts: 10 restarts in 10 seconds before giving up
    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 10,
      name: Ambrosia.Supervisor
    ]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("✨ Ambrosia listening on port #{config.port}")
        {:ok, pid}
      error ->
        Logger.error("Failed to start Ambrosia: #{inspect(error)}")
        error
    end
  end
  
  @impl true
  def stop(_state) do
    Logger.info("🌙 Ambrosia shutting down gracefully...")
    :ok
  end
  
  defp metrics_children do
    if System.get_env("METRICS_ENABLED") == "true" do
      port = String.to_integer(System.get_env("METRICS_PORT", "9568"))
      
      Logger.info("Starting metrics endpoint on port #{port}")
      
      [
        {Plug.Cowboy,
         scheme: :http,
         plug: Ambrosia.MetricsExporter,
         options: [port: port]}
      ]
    else
      []
    end
  end
  
  defp ranch_child_spec(config) do
    ranch_opts = %{
      socket_opts: [
        port: config.port,
        certfile: to_charlist(config.cert_file),
        keyfile: to_charlist(config.key_file),
        versions: [:"tlsv1.2", :"tlsv1.3"],
        verify: :verify_none,
        fail_if_no_peer_cert: false
      ],
      max_connections: config.max_connections,
      num_acceptors: System.schedulers_online() * 2
    }
    
    :ranch.child_spec(
      :ambrosia_listener,
      :ranch_ssl,
      ranch_opts.socket_opts,
      Ambrosia.Handler,
      config
    )
  end
  
  defp load_config do
    %{
      port: Application.get_env(:ambrosia, :port, 1965),
      root_dir: Application.get_env(:ambrosia, :root_dir, "./gemini"),
      cert_file: Application.get_env(:ambrosia, :cert_file, "./certs/cert.pem"),
      key_file: Application.get_env(:ambrosia, :key_file, "./certs/key.pem"),
      max_connections: Application.get_env(:ambrosia, :max_connections, 1000),
      request_timeout: Application.get_env(:ambrosia, :request_timeout, 10_000)
    }
  end
end
