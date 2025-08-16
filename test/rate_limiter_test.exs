defmodule Ambrosia.RateLimiterTest do
  use ExUnit.Case, async: false
  alias Ambrosia.RateLimiter

  setup do
    # Stop the application's rate limiter if running
    case Process.whereis(Ambrosia.RateLimiter) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid)
        Process.sleep(50)
    end

    # Start a fresh rate limiter
    {:ok, _pid} = start_supervised({Ambrosia.RateLimiter, [max_requests: 5, window_ms: 100]})

    :ok
  end

  describe "check_rate/1" do
    test "allows requests within limit" do
      ip = {127, 0, 0, 1}

      # First 5 requests should succeed
      for _ <- 1..5 do
        assert :ok = RateLimiter.check_rate(ip)
      end
    end

    test "rate limits after threshold" do
      ip = {192, 168, 1, 1}

      # Use up the bucket
      for _ <- 1..10 do
        RateLimiter.check_rate(ip)
      end

      # Next request should be rate limited
      assert :rate_limited = RateLimiter.check_rate(ip)
    end

    test "tokens refill over time" do
      ip = {10, 0, 0, 1}

      # Use up tokens
      for _ <- 1..10 do
        RateLimiter.check_rate(ip)
      end

      assert :rate_limited = RateLimiter.check_rate(ip)

      # Wait for refill
      Process.sleep(200)

      # Should be allowed again
      assert :ok = RateLimiter.check_rate(ip)
    end

    test "different IPs have separate buckets" do
      ip1 = {1, 1, 1, 1}
      ip2 = {2, 2, 2, 2}

      # Use up IP1's bucket
      for _ <- 1..10 do
        RateLimiter.check_rate(ip1)
      end

      assert :rate_limited = RateLimiter.check_rate(ip1)

      # IP2 should still work
      assert :ok = RateLimiter.check_rate(ip2)
    end

    test "handles IPv6 addresses" do
      ipv6 = {0, 0, 0, 0, 0, 0, 0, 1}
      assert :ok = RateLimiter.check_rate(ipv6)
    end
  end
end

