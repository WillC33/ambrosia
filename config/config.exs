import Config

config :logger, :console,
  format: {Ambrosia.LogFormatter, :format},
  metadata: [:peer_ip]

# Import environment specific config
import_config "#{config_env()}.exs"
