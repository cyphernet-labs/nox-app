import Config

config :backend, db_path: "app.db"

config :backend, BackendWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  # Keep on loopback; TLS is terminated by Caddy in front.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  url: [host: "localhost"],
  server: true,
  # Browser clients send an Origin header on WebSocket connect; native
  # desktop/mobile clients send none and are always accepted.
  # TODO: replace `false` with your real origins before exposing,
  # e.g. check_origin: ["https://app.example.com"]
  check_origin: false,
  # TODO: replace for production: mix phx.gen.secret
  secret_key_base:
    "dev-only-secret-key-base-change-me-0123456789abcdef0123456789abcdef",
  pubsub_server: Backend.PubSub,
  render_errors: [formats: [json: BackendWeb.ErrorJSON], layout: false]

config :phoenix, :json_library, Jason

config :logger, level: :info
