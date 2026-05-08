defmodule Babs.Citizens.DirectCli.Adapters.Copilot do
  @moduledoc """
  Direct adapter for GitHub Copilot CLI.
  """

  @behaviour Babs.Citizens.DirectCli.Adapter

  alias Babs.Citizens.DirectCli.Adapters.Common
  alias Babs.Citizens.ProviderRuntime.Result

  @impl true
  def provider, do: "copilot"

  @impl true
  def supports?(config) do
    case {Common.cli_name(config), Map.get(config, :cli_args, []) || []} do
      {"copilot", _args} -> true
      {"gh", ["copilot" | _rest]} -> true
      _other -> false
    end
  end

  @impl true
  def start_command(config, prompt, opts \\ []) do
    Common.command(config, provider(), base_args(config, prompt, []), opts)
  end

  @impl true
  def resume_command(config, provider_session_id, prompt, opts \\ []) do
    Common.command(
      config,
      provider(),
      base_args(config, prompt, ["--resume=#{provider_session_id}"]),
      Keyword.merge(opts, provider_session_id: provider_session_id, resume?: true)
    )
  end

  @impl true
  def parse_result(%{stdout: stdout} = artifacts, opts \\ []) do
    values = Common.decode_json_lines(stdout)
    text = Common.find_text(values)
    session_id = Common.find_session_id(values) || artifacts[:provider_session_id]

    cond do
      not is_binary(text) or String.trim(text) == "" ->
        {:error, :no_assistant_reply}

      true ->
        {:ok, direct_success(text, session_id, opts)}
    end
  end

  defp base_args(%{cli: cli, cli_args: ["copilot" | _rest], cwd: cwd}, prompt, extra)
       when is_binary(cli) do
    [cli, "copilot", "--"] ++ copilot_args(cwd, prompt, extra)
  end

  defp base_args(%{cli: cli, cwd: cwd}, prompt, extra),
    do: [cli] ++ copilot_args(cwd, prompt, extra)

  defp copilot_args(cwd, prompt, extra) do
    [
      "-p",
      prompt,
      "--output-format",
      "json",
      "--stream",
      "off",
      "--allow-all",
      "--no-ask-user",
      "-C",
      cwd
    ] ++ extra
  end

  defp direct_success(text, session_id, opts) do
    Result.direct_success(provider(), Common.clean_text(text, opts),
      provider_session_id: session_id,
      capabilities: %{"direct" => true, "resume" => is_binary(session_id)}
    )
  end
end
