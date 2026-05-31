defmodule Babs.MixProject do
  use Mix.Project

  def project do
    [
      app: :babs,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        summary: [threshold: 70],
        ignore_modules: [
          Babs.Application,
          BabsWeb.Endpoint,
          BabsWeb.ErrorHTML,
          BabsWeb.ErrorJSON,
          BabsWeb.Layouts,
          BabsWeb.Router,
          BabsWeb.Router.Helpers,
          BabsWeb.UserSocket
        ]
      ],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Babs.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:babs_citizens, in_umbrella: true},
      {:bandit, "~> 1.11"},
      {:file_system, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1.0", only: :test},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:tailwind, "~> 0.4.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"}
    ]
  end
end
