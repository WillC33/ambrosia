import Config

config :logger, level: :warning

config :ambrosia,
  # 100ms instead of 10 seconds for tests so they aren't taking as long to run
  request_timeout: 100
