defmodule Ambrosia.ConnectionManager do
  @moduledoc """
  Tracks active connections and enforces limits.
  """

  use GenServer
  require Logger

  defstruct [:max_connections, :connections, :rejected_count]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Register a new connection.
  Returns :ok or {:error, :too_many_connections}
  """
  def register_connection(ip) do
    GenServer.call(__MODULE__, {:register, ip})
  end

  @doc """
  Unregister a connection.
  """
  def unregister_connection(ip) do
    GenServer.cast(__MODULE__, {:unregister, ip})
  end

  @doc """
  Get current stats.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # GenServer callbacks

  @impl true
  def init(config) do
    state = %__MODULE__{
      max_connections: config[:max_connections] || 1000,
      connections: %{},
      rejected_count: 0
    }

    # Log stats periodically
    schedule_stats()

    {:ok, state}
  end

  @impl true
  def handle_call({:register, ip}, _from, state) do
    total_connections = map_size(state.connections)

    if total_connections >= state.max_connections do
      Logger.warning("Max connections reached (#{state.max_connections})")

      {:reply, {:error, :too_many_connections},
       %{state | rejected_count: state.rejected_count + 1}}
    else
      ip_connections = Map.get(state.connections, ip, 0)

      # Per-IP limit
      if ip_connections >= 10 do
        {:reply, {:error, :too_many_connections_from_ip}, state}
      else
        new_connections = Map.put(state.connections, ip, ip_connections + 1)
        {:reply, :ok, %{state | connections: new_connections}}
      end
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      active: map_size(state.connections),
      rejected: state.rejected_count,
      by_ip: state.connections
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:unregister, ip}, state) do
    new_connections =
      case Map.get(state.connections, ip) do
        nil -> state.connections
        1 -> Map.delete(state.connections, ip)
        n -> Map.put(state.connections, ip, n - 1)
      end

    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_info(:log_stats, state) do
    active = map_size(state.connections)

    if active > 0 do
      Logger.info("Active connections: #{active}, Rejected: #{state.rejected_count}")
    end

    schedule_stats()
    {:noreply, state}
  end

  defp schedule_stats do
    # Every 30 seconds
    Process.send_after(self(), :log_stats, 30_000)
  end
end
