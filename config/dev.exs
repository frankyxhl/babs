import Config

config :babs, BabsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  live_reload: [
    patterns: [
      ~r"apps/babs/lib/.*(ex)$"
    ]
  ],
  secret_key_base: String.duplicate("babs_dev_secret", 6)

config :phoenix, :plug_init_mode, :runtime
