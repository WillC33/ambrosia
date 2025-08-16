ExUnit.start()

# Stop the application if it's already running (from previous test runs)
Application.stop(:ambrosia)

# Clean up any existing ETS tables
if :ets.whereis(:ambrosia_rate_limits) != :undefined do
  :ets.delete(:ambrosia_rate_limits)
end
