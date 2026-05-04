defmodule Hardline.MixProject do
  use Mix.Project

  def project do
    [
      app: :hardline,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Hardline.Application, []},
      extra_applications: [:logger, :erlexec]
    ]
  end

  defp deps do
    [
      {:erlexec, "~> 2.3"},
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
