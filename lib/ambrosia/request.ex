defmodule Ambrosia.Request do
  @moduledoc """
  Gemini request parsing and validation.
  """

  defstruct [:scheme, :host, :port, :path, :query, :fragment, :raw, :peer_ip]
  @max_url_length 1024

  @doc """
  Parse a Gemini request line.
  Returns {:ok, %Request{}} or {:error, reason}
  """
  def parse(request_line) when is_binary(request_line) do
    unless String.ends_with?(request_line, "\r\n") do
      {:error, :missing_crlf}
    else
      # We will only accept lines with CRLF termniation but then discard it
      url = String.trim(request_line)

      # Check length
      if byte_size(url) > @max_url_length do
        {:error, :url_too_long}
      else
        parse_url(url)
      end
    end
  end

  defp parse_url("gemini://" <> rest) do
    with {:ok, host, port, path_and_query} <- parse_authority(rest) do
      {path, query} = split_query(path_and_query)

      decoded_path = path |> normalize_path |> URI.decode()

      {:ok,
       %__MODULE__{
         scheme: "gemini",
         host: host,
         port: port,
         path: decoded_path,
         query: query,
         raw: "gemini://#{rest}"
       }}
    end
  end

  defp parse_url(_), do: {:error, :invalid_scheme}

  defp parse_authority(rest) do
    case Regex.run(~r/^([^\/\?:]+)(?::(\d+))?(.*)$/, rest) do
      [_, host, "", path] ->
        {:ok, host, 1965, path}

      [_, host, port, path] ->
        case Integer.parse(port) do
          {port_num, ""} when port_num > 0 and port_num < 65_536 ->
            {:ok, host, port_num, path}

          _ ->
            {:error, :invalid_port}
        end

      _ ->
        {:error, :invalid_url}
    end
  end

  defp split_query(path_and_query) do
    case String.split(path_and_query, "?", parts: 2) do
      [path, query] -> {path, query}
      [path] -> {path, nil}
    end
  end

  defp normalize_path(""), do: "/"
  defp normalize_path(path), do: path

  defp permitted_hostname?(host, config) do
    config[:hostname] &&
      host in String.split(config[:hostname], ",", trim: true)
  end

  @doc """
  Check if request is valid for this server (not a proxy request).
  """
  def valid_for_server?(%__MODULE__{host: host}, config) do
    host in ["localhost", "127.0.0.1"] || permitted_hostname?(host, config)
  end

  @doc """
  Check if the requested path is safe (no traversal).
  """
  def safe_path?(%__MODULE__{path: path}) do
    # Reject ANY path with two dots, backslashing (dockerised on Linux) and %
    # If somebody wishes to be more clever with this they are welcome
    # Because the % rejection will cause some valid use cases to be considered unsafe
    not String.contains?(path, "..") &&
      not String.contains?(path, "\\")
  end
end
