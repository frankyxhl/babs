defmodule Mix.Tasks.Hardline.Validate do
  @moduledoc """
  Runs the Phase 0 Hardline validation harness.

      mix hardline.validate --profile smoke
      mix hardline.validate --profile full

  Use `--web-confirmed` only after separately running `mix hardline.web` and
  manually confirming the browser xterm.js byte path for the required duration.
  """

  use Mix.Task

  @shortdoc "Runs Hardline Phase 0 validation scenarios"

  @impl true
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          profile: :string,
          prefix: :string,
          command: :string,
          run_dir: :string,
          web_confirmed: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    Mix.Task.run("app.start")

    profile = Keyword.get(opts, :profile, "smoke")

    unless profile in Hardline.Validation.profiles() do
      Mix.raise(
        "unknown profile #{inspect(profile)}; expected one of #{inspect(Hardline.Validation.profiles())}"
      )
    end

    validation_opts =
      opts
      |> Keyword.take([:prefix, :command, :run_dir])
      |> Keyword.put(:profile, profile)
      |> Keyword.put(:web_confirmed?, Keyword.get(opts, :web_confirmed, false))

    {:ok, result} = Hardline.Validation.run(validation_opts)

    Mix.shell().info("Hardline validation complete")
    Mix.shell().info("Run dir: #{result.run_dir}")
    Mix.shell().info("Summary: #{result.summary}")
    Mix.shell().info("Events: #{result.log_path}")
  end
end
