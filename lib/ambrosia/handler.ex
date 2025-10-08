defmodule Ambrosia.Handler do
  @moduledoc """
  Handles individual Gemini connections.
  Each connection runs in its own process for fault isolation.
  """

  @behaviour :ranch_protocol

  require Logger
  alias Ambrosia.{Response, Request, FileServer, RateLimiter, Telemetry}

  @impl true
  def start_link(ref, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  def init(ref, transport, config) do
    # Start telemetry
    start_time = System.monotonic_time()
    metadata = %{transport: transport}

    # Perform TLS handshake
    case :ranch.handshake(ref) do
      {:ok, socket} ->
        # Get peer info for logging/rate limiting
        {:ok, {peer_ip, _port}} = transport.peername(socket)
        ip_string = peer_ip |> :inet.ntoa() |> to_string()

        Logger.metadata(peer_ip: ip_string)
        Logger.debug("New connection from #{ip_string}")

        # Check rate limit
        case RateLimiter.check_rate(peer_ip) do
          :ok ->
            handle_connection(socket, transport, config, metadata, start_time)

          :rate_limited ->
            Logger.warning("Rate limited: #{ip_string}")

            Response.send(
              socket,
              transport,
              {44, "Slow down! Rate limit exceeded"}
            )

            transport.close(socket)
        end

      {:error, reason} ->
        Logger.error("Handshake failed: #{inspect(reason)}")
    end
  end

  defp handle_connection(socket, transport, config, metadata, start_time) do
    # Get peer IP for the request
    {:ok, {peer_ip, _port}} = transport.peername(socket)
    ip_string = peer_ip |> :inet.ntoa() |> to_string()

    # Set receive timeout
    transport.setopts(socket, [{:active, false}, {:packet, :line}])

    case transport.recv(socket, 1024, config.request_timeout) do
      {:ok, request_line} ->
        # Parse and add peer_ip to request
        case Request.parse(request_line) do
          {:ok, request} ->
            # Add peer_ip to the request struct
            request_with_ip = %{request | peer_ip: ip_string}
            Logger.info("Request: #{request_with_ip.path}")

            response = process_request({:ok, request_with_ip}, config)
            Response.send(socket, transport, response)

          {:error, reason} ->
            response = process_request({:error, reason}, config)
            Response.send(socket, transport, response)
        end

        # Emit metrics
        duration = System.monotonic_time() - start_time
        Telemetry.emit(:request_complete, %{duration: duration}, metadata)

      {:error, :timeout} ->
        Logger.warning("Request timeout")
        Response.send(socket, transport, {59, "Request timeout"})

      {:error, reason} ->
        Logger.error("Receive error: #{inspect(reason)}")
    end

    # Clean up connection as Gemini doesn't keep it open!
    transport.close(socket)
  end

  defp process_request({:ok, %Request{peer_ip: peer_ip} = req}, config) do
    cond do
      # Check if it's a gemini:// URL for this server
      not Request.valid_for_server?(req, config) ->
        {53, "Proxy request refused"}

      # Path traversal check
      not Request.safe_path?(req) ->
        Logger.metadata(peer_ip: peer_ip)

        Logger.warning(
          "SECURITY: Path traversal attempt blocked! Request: #{req.path}"
        )

        {51, "Not found"}

      # Serve the file
      true ->
        FileServer.serve(req, config)
    end
  end

  defp process_request({:error, reason}, _config) do
    Logger.warning("Bad request: #{reason}")
    {59, "Bad request"}
  end
end
