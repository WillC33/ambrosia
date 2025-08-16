defmodule Ambrosia.Telemetry do
  @moduledoc """
  Telemetry metrics for monitoring server health.
  """

  use Supervisor
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def emit(event, measurements, metadata \\ %{}) do
    :telemetry.execute(
      [:ambrosia | List.wrap(event)],
      measurements,
      metadata
    )
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_vm_metrics, []}
    ]
  end

  def emit_vm_metrics do
    # Get Ranch info safely
    active_connections =
      try do
        case :ranch.info(:ambrosia_listener) do
          info when is_list(info) ->
            Keyword.get(info, :active_connections, 0)

          _ ->
            0
        end
      rescue
        _ -> 0
      end

    emit(:vm, %{
      memory_total: :erlang.memory(:total),
      memory_processes: :erlang.memory(:processes),
      memory_ets: :erlang.memory(:ets),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      schedulers: :erlang.system_info(:schedulers_online),
      active_connections: active_connections
    })

    # Log stats periodically
    Logger.info(
      "Stats: #{:erlang.system_info(:process_count)} processes, " <>
        "#{active_connections} connections"
    )
  end

  @doc """
  Attach handlers for logging metrics.
  """
  def attach_handlers do
    :telemetry.attach(
      "ambrosia-request-handler",
      [:ambrosia, :request_complete],
      &handle_request_complete/4,
      nil
    )

    :telemetry.attach(
      "ambrosia-vm-handler",
      [:ambrosia, :vm],
      &handle_vm_metrics/4,
      nil
    )
  end

  defp handle_request_complete(_event, %{duration: duration}, metadata, _config) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    Logger.debug("Request completed in #{duration_ms}ms", metadata)
  end

  defp handle_vm_metrics(_event, measurements, _metadata, _config) do
    # 500MB
    if measurements.memory_total > 500_000_000 do
      Logger.warning("High memory usage: #{div(measurements.memory_total, 1_000_000)}MB")
    end
  end
end
