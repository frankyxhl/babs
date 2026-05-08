defmodule Babs.Citizens.ProviderRuntime.Inventory do
  @moduledoc """
  Static inventory for current provider/backend capability contracts.
  """

  alias Babs.Citizens.DirectCli.Adapters
  alias Babs.Citizens.ImportedHardline
  alias Babs.Citizens.ProviderRuntime.Contract

  @output_limit 65_536

  def all do
    [
      direct("claude", "claude --print --output-format json"),
      direct("codex", "codex exec --json"),
      direct("copilot", "copilot -p --output-format json"),
      direct("fake", "babs-fake-ai --reply"),
      hardline("babs"),
      hardline("external"),
      reserved("droid", "hardline"),
      reserved("pi", "hardline"),
      reserved("ai_cli", "lazy_tmux")
    ]
  end

  def get(provider, backend, opts \\ []) do
    ownership = Keyword.get(opts, :ownership, "babs")

    all()
    |> Enum.find(
      &(&1.provider == provider and &1.backend == backend and &1.ownership == ownership)
    )
    |> case do
      nil -> {:error, {:unknown_provider_runtime, provider, backend, ownership}}
      contract -> {:ok, contract}
    end
  end

  def for_config(config) when is_map(config) do
    case ticket_backend(config) do
      "direct_cli" ->
        with {:ok, adapter} <- Adapters.resolve(adapter_config(config)) do
          get(adapter.provider(), "direct_cli")
        end

      "hardline" ->
        ownership = if ImportedHardline.external?(metadata(config)), do: "external", else: "babs"
        get("ai_cli", "hardline", ownership: ownership)

      "lazy_tmux" ->
        get("ai_cli", "lazy_tmux", ownership: "reserved")

      backend ->
        {:error, {:unsupported_ticket_backend, backend}}
    end
  end

  def capability_map(%Contract{} = contract), do: {:ok, Contract.to_map(contract)}

  def capability_map(config) when is_map(config) do
    with {:ok, contract} <- for_config(config) do
      capability_map(contract)
    end
  end

  defp direct(provider, command_shape) do
    Contract.new!(%{
      provider: provider,
      backend: "direct_cli",
      ownership: "babs",
      status: "supported",
      command: %{"shape" => command_shape},
      cwd_policy: %{"mode" => "resolved_cwd"},
      env_policy: %{"mode" => "allowlisted_process_env"},
      launch_profiles: ["trusted_autonomous"],
      input_modes: ["argv_prompt"],
      resume: %{"supported" => true, "mode" => "provider_session_id"},
      session_id_parser: %{"supported" => true},
      reply_parser: %{"supported" => true},
      capabilities: %{
        "execute" => true,
        "direct_turn" => true,
        "resume" => true,
        "interactive_attach" => false,
        "kill_authority" => false,
        "detach_authority" => false
      },
      version_fingerprint: %{"mode" => "deferred"},
      timeouts: %{"execution_ms" => 120_000},
      output_limits: %{"stdout_bytes" => @output_limit, "stderr_bytes" => @output_limit},
      diagnostics: %{"redacted" => true, "operator_visible" => true},
      raw_artifact_refs: [],
      interactive_attach: %{"supported" => false}
    })
  end

  defp hardline(ownership) do
    external? = ownership == "external"

    Contract.new!(%{
      provider: "ai_cli",
      backend: "hardline",
      ownership: ownership,
      status: "supported",
      command: %{"shape" => "tmux hardline interactive process"},
      cwd_policy: %{"mode" => "resolved_cwd_or_imported_pane"},
      env_policy: %{"mode" => "spawn_env_or_imported_existing"},
      launch_profiles: ["safe_interactive", "trusted_autonomous"],
      input_modes: ["terminal_injection"],
      resume: %{"supported" => true, "mode" => "tmux_session"},
      session_id_parser: %{"supported" => false},
      reply_parser: %{"supported" => true, "mode" => "transcript_or_jsonl_capture"},
      capabilities: %{
        "execute" => true,
        "direct_turn" => false,
        "resume" => true,
        "interactive_attach" => true,
        "kill_authority" => not external?,
        "detach_authority" => true
      },
      version_fingerprint: %{"mode" => "tmux_metadata"},
      timeouts: %{"capture_ms" => 120_000},
      output_limits: %{"capture_bytes" => @output_limit},
      diagnostics: %{"redacted" => true, "operator_visible" => true},
      raw_artifact_refs: [%{"kind" => "transcript_cursor"}],
      interactive_attach: %{"supported" => true}
    })
  end

  defp reserved(provider, backend) do
    Contract.new!(%{
      provider: provider,
      backend: backend,
      ownership: "reserved",
      status: "deferred",
      command: %{"shape" => "reserved"},
      cwd_policy: %{"mode" => "deferred"},
      env_policy: %{"mode" => "deferred"},
      launch_profiles: [],
      input_modes: [],
      resume: %{"supported" => false},
      session_id_parser: %{"supported" => false},
      reply_parser: %{"supported" => false},
      capabilities: %{
        "execute" => false,
        "direct_turn" => false,
        "resume" => false,
        "interactive_attach" => false,
        "kill_authority" => false,
        "detach_authority" => false
      },
      version_fingerprint: %{"mode" => "deferred"},
      timeouts: %{},
      output_limits: %{},
      diagnostics: %{"redacted" => true},
      raw_artifact_refs: [],
      interactive_attach: %{"supported" => false}
    })
  end

  defp ticket_backend(config),
    do: Map.get(config, :ticket_backend) || Map.get(config, "ticket_backend") || "hardline"

  defp adapter_config(config) do
    config
    |> put_atom_key(:cli, "cli", "")
    |> put_atom_key(:cli_args, "cli_args", [])
  end

  defp put_atom_key(config, atom_key, string_key, default) do
    value = Map.get(config, atom_key) || Map.get(config, string_key) || default
    Map.put(config, atom_key, value)
  end

  defp metadata(config), do: Map.get(config, :metadata) || Map.get(config, "metadata") || %{}
end
