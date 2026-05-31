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
      elixirc_paths: elixirc_paths(Mix.env()),
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
      extra_applications: [:logger, :erlexec, :ecto_sql, :inets]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.22.0"},
      {:erlexec, "~> 2.3"},
      {:file_system, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:mdex, "~> 0.12.2"},
      {:phoenix_pubsub, "~> 2.1"},
      {:toml, "~> 0.7.0"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
