import Config

if config_env() == :prod do
  config :ambrosia,
    port: String.to_integer(System.get_env("GEMINI_PORT", "1965")),
    root_dir: System.get_env("ROOT_DIR", "/app/gemini"),
    cert_file: System.get_env("CERT_FILE", "/certs/cert.pem"),
    key_file: System.get_env("KEY_FILE", "/certs/key.pem"),
    max_connections: String.to_integer(System.get_env("MAX_CONNECTIONS", "1000")),
    request_timeout: String.to_integer(System.get_env("REQUEST_TIMEOUT", "10000"))
end
