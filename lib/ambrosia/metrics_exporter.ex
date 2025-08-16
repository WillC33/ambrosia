defmodule Ambrosia.MetricsExporter do
  @moduledoc """
  Simple Prometheus metrics exporter for Ambrosia telemetry.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    metrics = collect_metrics()
    
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  defp collect_metrics do
    # Get current telemetry data
    active_connections = get_active_connections()
    memory = :erlang.memory()
    
    """
    # HELP ambrosia_connections_active Number of active Gemini connections
    # TYPE ambrosia_connections_active gauge
    ambrosia_connections_active #{active_connections}
    
    # HELP ambrosia_memory_bytes Memory usage in bytes
    # TYPE ambrosia_memory_bytes gauge
    ambrosia_memory_bytes{type="total"} #{memory[:total]}
    ambrosia_memory_bytes{type="processes"} #{memory[:processes]}
    ambrosia_memory_bytes{type="ets"} #{memory[:ets]}
    
    # HELP ambrosia_erlang_processes Number of Erlang processes
    # TYPE ambrosia_erlang_processes gauge
    ambrosia_erlang_processes #{:erlang.system_info(:process_count)}
    
    # HELP ambrosia_erlang_ports Number of Erlang ports
    # TYPE ambrosia_erlang_ports gauge
    ambrosia_erlang_ports #{:erlang.system_info(:port_count)}
    
    # HELP ambrosia_schedulers Number of schedulers online
    # TYPE ambrosia_schedulers gauge
    ambrosia_schedulers #{:erlang.system_info(:schedulers_online)}
    
    # HELP ambrosia_up Is the server up
    # TYPE ambrosia_up gauge
    ambrosia_up 1
    """
  end
  
  defp get_active_connections do
    try do
      case :ranch.info(:ambrosia_listener) do
        info when is_list(info) ->
          Keyword.get(info, :active_connections, 0)
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end
end
