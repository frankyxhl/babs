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
      {:phoenix, "~> 1.8"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"}
    ]
  end
end
