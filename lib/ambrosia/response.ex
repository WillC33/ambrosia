defmodule Ambrosia.Response do
  @moduledoc """
  Gemini response formatting and sending.
  """

  require Logger

  @doc """
  Send a response over the socket.
  Accepts:
  - {status, meta} for header-only responses
  - {status, meta, body} for full responses
  """
  def send(socket, transport, {status, meta}) do
    header = "#{status} #{meta}\r\n"
    transport.send(socket, header)
  end

  def send(socket, transport, {status, meta, body}) do
    header = "#{status} #{meta}\r\n"

    # Send header
    case transport.send(socket, header) do
      :ok ->
        # Send body (stream for large files)
        send_body(socket, transport, body)

      error ->
        Logger.error("Failed to send header: #{inspect(error)}")
        error
    end
  end

  defp send_body(socket, transport, body) when is_binary(body) do
    # For small content, send directly
    # 1MB threshold
    if byte_size(body) < 1_000_000 do
      transport.send(socket, body)
    else
      # Stream large content in chunks
      stream_body(socket, transport, body)
    end
  end

  defp stream_body(socket, transport, body) do
    # Send in 64KB chunks
    chunk_size = 65_536

    body
    |> :binary.bin_to_list()
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case transport.send(socket, :binary.list_to_bin(chunk)) do
        :ok ->
          {:cont, :ok}

        error ->
          Logger.error("Stream error: #{inspect(error)}")
          {:halt, error}
      end
    end)
  end
end

