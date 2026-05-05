import Config

config :babs, BabsWeb.Endpoint,
  check_origin: true,
  code_reloader: false

config :logger, level: :info
config :phoenix, :plug_init_mode, :runtime
