import Config

if config_env() == :prod do
  hostname = System.get_env("HOSTNAME")

  unless hostname do
    raise "HOSTNAME environment variable is required in production"
  end

  config :ambrosia,
    port: String.to_integer(System.get_env("GEMINI_PORT", "1965")),
    root_dir: System.get_env("ROOT_DIR", "/app/gemini"),
    cert_file: System.get_env("CERT_FILE", "/certs/cert.pem"),
    key_file: System.get_env("KEY_FILE", "/certs/key.pem"),
    max_connections:
      String.to_integer(System.get_env("MAX_CONNECTIONS", "1000")),
    request_timeout:
      String.to_integer(System.get_env("REQUEST_TIMEOUT", "10000")),
    hostname: hostname,
    rate_limit_requests:
      String.to_integer(System.get_env("RATE_LIMIT_REQUESTS", "10")),
    rate_limit_window_ms:
      String.to_integer(System.get_env("RATE_LIMIT_WINDOW_MS", "1000"))
end
