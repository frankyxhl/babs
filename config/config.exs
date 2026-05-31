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
  config_dir: "citizens",
  autostart: config_env() != :test,
  auto_migrate: config_env() in [:dev, :test],
  ecto_repos: [Babs.Citizens.Repo]

config :babs_citizens, Babs.Citizens.Repo,
  log: false,
  stacktrace: config_env() == :dev,
  telemetry_prefix: [:babs_citizens, :repo]

config :babs, Babs.DevReloader,
  enabled: config_env() == :dev,
  watch_path: "apps/babs_citizens/lib",
  debounce_ms: 300

config :babs, :kitchen_sink_enabled, config_env() in [:dev, :test]

config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
        --input=apps/babs/assets/css/app.css
        --output=apps/babs/priv/static/css/app.css
      ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :telemetry_poller, default: false

import_config "#{config_env()}.exs"
