defmodule Ambrosia.RateLimiter do
  @moduledoc """
  Token bucket rate limiter using ETS for fast, concurrent access.
  Each IP gets a bucket that refills over time. Probably no one is DDoSing Gemini
  But we never know...
  """

  use GenServer
  require Logger

  @table_name :ambrosia_rate_limits
  # Clean old entries every minute
  @cleanup_interval 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an IP is rate limited.
  Returns :ok or :rate_limited
  """
  def check_rate(ip) do
    now = System.system_time(:millisecond)

    case :ets.lookup(@table_name, ip) do
      [{^ip, tokens, last_refill}] ->
        # Calculate tokens to add based on time elapsed
        elapsed = now - last_refill
        # 10 tokens per second
        refill_rate = 10 / 1000
        new_tokens = min(10, tokens + elapsed * refill_rate)

        if new_tokens >= 1 do
          # Consume a token
          :ets.insert(@table_name, {ip, new_tokens - 1, now})
          :ok
        else
          :rate_limited
        end

      [] ->
        # New IP, give them a full bucket
        :ets.insert(@table_name, {ip, 9, now})
        :ok
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    # Schedule cleanup
    schedule_cleanup()

    state = %{
      max_requests: Keyword.get(opts, :max_requests, 100),
      window_ms: Keyword.get(opts, :window_ms, 1000)
    }

    Logger.info("Rate limiter started: #{state.max_requests} requests per #{state.window_ms}ms")

    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove entries older than 5 minutes
    cutoff = System.system_time(:millisecond) - 300_000

    :ets.select_delete(@table_name, [
      {{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
