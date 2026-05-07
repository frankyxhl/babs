defmodule Babs.Citizens.DirectCli.Adapters.Codex do
  @moduledoc """
  Direct adapter for `codex exec --json`.
  """

  @behaviour Babs.Citizens.DirectCli.Adapter

  alias Babs.Citizens.DirectCli.Adapters.Common

  @impl true
  def provider, do: "codex"

  @impl true
  def supports?(config), do: Common.cli_name(config) == "codex"

  @impl true
  def start_command(config, prompt, opts \\ []) do
    Common.command(
      config,
      provider(),
      cli_args(config) ++
        [
          "exec",
          "--json",
          "--cd",
          config.cwd,
          "--dangerously-bypass-approvals-and-sandbox",
          prompt
        ],
      opts
    )
  end

  @impl true
  def resume_command(config, provider_session_id, prompt, opts \\ []) do
    Common.command(
      config,
      provider(),
      cli_args(config) ++
        [
          "exec",
          "resume",
          "--json",
          "--dangerously-bypass-approvals-and-sandbox",
          provider_session_id,
          prompt
        ],
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
        {:ok,
         %{
           provider: provider(),
           text: Common.clean_text(text, opts),
           provider_session_id: session_id,
           capabilities: %{"direct" => true, "resume" => is_binary(session_id)}
         }}
    end
  end

  defp cli_args(config), do: [config.cli] ++ (config.cli_args || [])
end
