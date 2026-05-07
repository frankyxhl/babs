defmodule Babs.Citizens.DirectCli.Adapters.Claude do
  @moduledoc """
  Direct adapter for Claude Code `claude -p`.
  """

  @behaviour Babs.Citizens.DirectCli.Adapter

  alias Babs.Citizens.DirectCli.Adapters.Common

  @impl true
  def provider, do: "claude"

  @impl true
  def supports?(config), do: Common.cli_name(config) == "claude"

  @impl true
  def start_command(config, prompt, opts \\ []) do
    session_id = Keyword.get(opts, :provider_session_id) || Ecto.UUID.generate()

    Common.command(
      config,
      provider(),
      [config.cli, "--print", "--output-format", "json", "--session-id", session_id, prompt],
      Keyword.merge(opts, provider_session_id: session_id)
    )
  end

  @impl true
  def resume_command(config, provider_session_id, prompt, opts \\ []) do
    Common.command(
      config,
      provider(),
      [config.cli, "--print", "--output-format", "json", "--resume", provider_session_id, prompt],
      Keyword.merge(opts, provider_session_id: provider_session_id, resume?: true)
    )
  end

  @impl true
  def parse_result(%{stdout: stdout} = artifacts, opts \\ []) do
    values = Common.decode_json_object(stdout)
    text = Common.find_text(values) || artifacts[:stderr]
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
end
