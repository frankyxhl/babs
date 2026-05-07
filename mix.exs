defmodule Babs.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      aliases: aliases()
    ]
  end

  defp deps, do: []

  defp aliases do
    [
      setup: ["deps.get", "assets.setup"],
      "assets.setup": ["tailwind.install --if-missing"],
      "assets.build": ["tailwind default"],
      "assets.deploy": ["tailwind default --minify"],
      test: ["test"]
    ]
  end
end
