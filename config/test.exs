import Config

config :babs, BabsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("babs_test_secret", 6)

config :babs_citizens, autostart: false

config :logger, level: :warning
