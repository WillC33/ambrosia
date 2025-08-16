defmodule Ambrosia.RateLimiter do
  @moduledoc """
  Token bucket rate limiter using ETS for fast, concurrent access.
  Each IP gets a bucket that refills over time.
  """

  use GenServer
  require Logger

  @table_name :ambrosia_rate_limits
  @config_key :rate_limiter_config
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

    # Get config from ETS
    [{@config_key, max_tokens, window_ms}] =
      :ets.lookup(@table_name, @config_key)

    # tokens per millisecond
    refill_rate = max_tokens / window_ms

    case :ets.lookup(@table_name, ip) do
      [{^ip, tokens, last_refill}] ->
        # Calculate tokens to add based on time elapsed
        elapsed = now - last_refill
        new_tokens = min(max_tokens, tokens + elapsed * refill_rate)

        if new_tokens >= 1 do
          # Consume a token
          :ets.insert(@table_name, {ip, new_tokens - 1, now})
          :ok
        else
          :rate_limited
        end

      [] ->
        # New IP, give them a full bucket minus one token
        :ets.insert(@table_name, {ip, max_tokens - 1, now})
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

    # Get config from opts
    max_requests = Keyword.get(opts, :max_requests, 10)
    window_ms = Keyword.get(opts, :window_ms, 1000)

    # Store config in ETS for check_rate to use
    :ets.insert(@table_name, {@config_key, max_requests, window_ms})

    # Schedule cleanup
    schedule_cleanup()

    state = %{
      max_requests: max_requests,
      window_ms: window_ms
    }

    Logger.info(
      "Rate limiter started: #{max_requests} requests per #{window_ms}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove entries older than 5 minutes
    cutoff = System.system_time(:millisecond) - 300_000

    # Don't delete the config entry!
    :ets.select_delete(@table_name, [
      {{:"$1", :_, :"$2"},
       [{:andalso, {:"/=", :"$1", @config_key}, {:<, :"$2", cutoff}}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end

