import Config

config :babs, BabsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BabsWeb.ErrorHTML, json: BabsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Babs.Citizens.PubSub,
  live_view: [signing_salt: "babs-phase1"]

config :babs_citizens,
  root: File.cwd!(),
  config_dir: "citizens",
  autostart: config_env() != :test

config :babs, Babs.DevReloader,
  enabled: config_env() == :dev,
  root: File.cwd!(),
  watch_path: "apps/babs_citizens/lib",
  debounce_ms: 300

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
