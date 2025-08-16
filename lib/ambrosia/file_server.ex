defmodule Ambrosia.FileServer do
  @moduledoc """
  Serves files from the filesystem with proper MIME type detection.
  """

  require Logger
  alias Ambrosia.Request

  @index_files ["index.gmi", "index.gemini"]
  # 100MB limit per Gemini best practices
  @max_file_size 100 * 1024 * 1024

  @doc """
  Serve a file based on the request.
  Returns {status_code, meta, body} or {status_code, meta}
  """
  def serve(%Request{path: path, peer_ip: peer_ip}, config) do
    with {:ok, safe_path} <- validate_and_normalize_path(path, config.root_dir),
         {:ok, file_info} <- get_file_info(safe_path) do
      case file_info do
        :directory -> serve_directory(safe_path, config)
        :file -> serve_file(safe_path)
        :not_found -> {51, "Not found"}
      end
    else
      {:error, :traversal} ->
        Logger.metadata(peer_ip: peer_ip)

        Logger.critical(
          "CRITICAL SECURITY: Path traversal bypassed handler validation but was still successfully blocked! IP: #{peer_ip}, Request: #{path}"
        )

        # This should NEVER happen if Handler is working correctly
        # Consider additional actions:
        # - Alert administrators
        # - Add IP to immediate blocklist
        # - Increment security metrics
        # - Pause Gemini server 
        {51, "Not found"}
    end
  end

  # Validates path is within root_dir and returns the normalized absolute path.
  # Single source of truth for path validation.
  defp validate_and_normalize_path(request_path, root_dir) do
    # Normalize the root directory once
    normalized_root = Path.expand(root_dir)

    # Clean and join the paths
    clean_path = String.trim_leading(request_path, "/")
    requested_path = Path.join(normalized_root, clean_path) |> Path.expand()

    # Security check: ensure path is within root
    # Must be either the root itself or a subdirectory/file within it
    cond do
      requested_path == normalized_root ->
        {:ok, requested_path}

      String.starts_with?(requested_path, normalized_root <> "/") ->
        {:ok, requested_path}

      true ->
        {:error, :traversal}
    end
  end

  # Get file type information without multiple stat calls
  defp get_file_info(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :directory}} -> {:ok, :directory}
      {:ok, %File.Stat{type: :regular}} -> {:ok, :file}
      {:error, :enoent} -> {:ok, :not_found}
      {:error, _} -> {:ok, :not_found}
    end
  end

  defp serve_directory(dir_path, config) do
    # Try index files first
    index_result =
      Enum.find_value(@index_files, fn index_file ->
        index_path = Path.join(dir_path, index_file)

        case File.stat(index_path) do
          {:ok, %File.Stat{type: :regular}} -> serve_file(index_path)
          _ -> nil
        end
      end)

    index_result || generate_directory_listing(dir_path, config.root_dir)
  end

  defp serve_file(file_path) do
    # Check file size before reading (Gemini best practice for large files)
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size}} when size > @max_file_size ->
        {59, "File too large (>100MB)"}

      {:ok, _stat} ->
        serve_if_valid(file_path)

      {:error, _} ->
        {51, "Not found"}
    end
  end

  defp serve_if_valid(file_path) do
    # Check if file type is supported in Geminispace
    case detect_mime(file_path) do
      :unsupported ->
        {59, "File type not supported"}

      mime ->
        # Path already validated - read file content into memory
        # This might eventually need a better approach for large documents
        case :file.read_file(file_path) do
          {:ok, content} ->
            {20, mime, content}

          {:error, :enoent} ->
            {51, "Not found"}

          {:error, :eacces} ->
            {50, "Permission denied"}

          {:error, reason} ->
            Logger.error("File read error: #{inspect(reason)}")
            {40, "Temporary failure"}
        end
    end
  end

  defp generate_directory_listing(dir_path, root_dir) do
    case File.ls(dir_path) do
      {:ok, files} ->
        # Both paths need to be expanded for relative_to to work correctly
        normalized_dir = Path.expand(dir_path)
        normalized_root = Path.expand(root_dir)

        relative_path = Path.relative_to(normalized_dir, normalized_root)

        display_path =
          if relative_path == ".", do: "/", else: "/" <> relative_path

        listing =
          build_directory_gemtext(
            display_path,
            normalized_dir,
            files,
            normalized_root
          )

        {20, "text/gemini", listing}

      {:error, _} ->
        {51, "Not found"}
    end
  end

  defp build_directory_gemtext(display_path, dir_path, files, root_dir) do
    header = "# Index of #{display_path}\n\n"

    # Parent directory link (if not at root)
    parent_link =
      if Path.expand(dir_path) != Path.expand(root_dir) do
        "=> ../ Parent directory\n"
      else
        ""
      end

    # Build links for each file/directory
    # Only include files that are actually accessible
    file_links =
      files
      |> Enum.sort()
      |> Enum.filter(fn file ->
        file_path = Path.join(dir_path, file)

        # Check if we can actually stat this file
        case File.stat(file_path) do
          {:ok, _stat} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn file ->
        file_path = Path.join(dir_path, file)
        stat = File.stat!(file_path)

        case stat.type do
          :directory ->
            "=> #{URI.encode(file)}/ #{file}/"

          :regular ->
            "=> #{URI.encode(file)} #{file}"

          _ ->
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.join("\n")

    header <> parent_link <> file_links
  end

  defp detect_mime(path) do
    case Path.extname(path) |> String.downcase() do
      # ONLY serve Gemini native format - provides security & philosophy alignment
      ".gmi" -> "text/gemini"
      ".gemini" -> "text/gemini"
      # Reject everything else 
      # Though here is the spot for serving other MIME types
      # Should you wish to do so
      _ -> :unsupported
    end
  end
end
