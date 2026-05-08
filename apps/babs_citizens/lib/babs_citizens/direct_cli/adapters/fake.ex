defmodule Babs.Citizens.DirectCli.Adapters.Fake do
  @moduledoc """
  Deterministic direct adapter for tests and browser-harness BDD only.
  """

  @behaviour Babs.Citizens.DirectCli.Adapter

  alias Babs.Citizens.DirectCli.Adapters.Common
  alias Babs.Citizens.ProviderRuntime.Result

  @impl true
  def provider, do: "fake"

  @impl true
  def supports?(config), do: Common.cli_name(config) == "babs-fake-ai"

  @impl true
  def start_command(config, prompt, opts \\ []) do
    session_id = Keyword.get(opts, :provider_session_id) || "fake-session-#{config.slug}"

    Common.command(
      config,
      provider(),
      [config.cli, "--session", session_id, "--reply", prompt],
      Keyword.merge(opts, provider_session_id: session_id)
    )
  end

  @impl true
  def resume_command(config, provider_session_id, prompt, opts \\ []) do
    Common.command(
      config,
      provider(),
      [config.cli, "--resume", provider_session_id, "--reply", prompt],
      Keyword.merge(opts, provider_session_id: provider_session_id, resume?: true)
    )
  end

  @impl true
  def parse_result(%{stdout: stdout} = artifacts, opts \\ []) do
    values = Common.decode_json_object(stdout)

    text =
      Common.find_text(values) ||
        artifacts[:text] ||
        stdout

    session_id = Common.find_session_id(values) || artifacts[:provider_session_id]

    {:ok,
     Result.direct_success(provider(), Common.clean_text(text, opts),
       provider_session_id: session_id,
       capabilities: %{"direct" => true, "resume" => is_binary(session_id)}
     )}
  end
end
