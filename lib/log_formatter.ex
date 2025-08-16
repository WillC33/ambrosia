defmodule Ambrosia.LogFormatter do
  def format(level, message, timestamp, metadata) do
    datetime = format_time(timestamp)
    ip = Keyword.get(metadata, :peer_ip, "no-ip")
    "#{datetime}: [#{level}] [#{ip}] #{message}\n"
  rescue
    _ -> "LOG ERROR: could not format message\n"
  end

  defp format_time({{year, month, day}, {hour, min, sec, _}}) do
    date = "#{year}-#{format_2digit(month)}-#{format_2digit(day)}"
    time = "#{format_2digit(hour)}:#{format_2digit(min)}:#{format_2digit(sec)}"
    "#{date} #{time}"
  end

  defp format_2digit(num), do: num |> Integer.to_string() |> String.pad_leading(2, "0")
end

