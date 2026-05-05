defmodule Babs.Citizens.MixProject do
  use Mix.Project

  def project do
    [
      app: :babs_citizens,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        summary: [threshold: 80],
        ignore_modules: [
          Mix.Tasks.Babs.GateA
        ]
      ],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Babs.Citizens.Application, []},
      extra_applications: [:logger, :erlexec]
    ]
  end

  defp deps do
    [
      {:erlexec, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:toml, "~> 0.7.0"}
    ]
  end
end
