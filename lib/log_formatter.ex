defmodule Ambrosia.LogFormatter do
  @moduledoc """
  Formats frontmatter of logs into a friendlier format
  """

  @format Logger.Formatter.compile("$date $time: [$level] $message\n")

  def format(level, message, timestamp, metadata) do
    msg =
      case Keyword.fetch(metadata, :peer_ip) do
        {:ok, ip} -> ["[#{ip}] ", format_message(message)]
        :error -> format_message(message)
      end

    Logger.Formatter.format(@format, level, msg, timestamp, [])
  end

  defp format_message(msg), do: msg
end
