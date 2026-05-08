defmodule Babs.Citizens.ProviderRuntime.ContractTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.ProviderRuntime.Contract

  test "normalizes a provider runtime contract into a public-safe capability map" do
    assert {:ok, contract} = Contract.new(valid_attrs())

    assert %Contract{} = contract

    assert Contract.to_map(contract) == %{
             "provider" => "claude",
             "backend" => "direct_cli",
             "ownership" => "babs",
             "status" => "supported",
             "command" => %{"shape" => "claude --print --output-format json"},
             "cwd_policy" => %{"mode" => "resolved_cwd"},
             "env_policy" => %{"mode" => "allowlist"},
             "launch_profiles" => ["safe_interactive", "trusted_autonomous"],
             "input_modes" => ["argv_prompt"],
             "resume" => %{"supported" => true, "mode" => "provider_session_id"},
             "session_id_parser" => %{"supported" => true},
             "reply_parser" => %{"supported" => true},
             "capabilities" => %{"direct_turn" => true},
             "version_fingerprint" => %{"mode" => "deferred"},
             "timeouts" => %{"execution_ms" => 120_000},
             "output_limits" => %{"stdout_bytes" => 65_536, "stderr_bytes" => 65_536},
             "diagnostics" => %{"redacted" => true},
             "raw_artifact_refs" => [],
             "interactive_attach" => %{"supported" => false}
           }
  end

  test "rejects raw artifact refs that expose paths" do
    assert {:error, {:unsafe_raw_artifact_ref, %{"path" => "redacted-local-path"}}} =
             valid_attrs()
             |> Map.put(:raw_artifact_refs, [%{"path" => "redacted-local-path"}])
             |> Contract.new()

    assert {:error, {:unsafe_raw_artifact_ref, %{"path" => "nested-redacted-local-path"}}} =
             valid_attrs()
             |> Map.put(:raw_artifact_refs, [
               %{"cursor" => %{"path" => "nested-redacted-local-path"}}
             ])
             |> Contract.new()
  end

  test "rejects unknown contract fields without raising" do
    assert {:error, {:unknown_field, "unexpected"}} = Contract.new(%{"unexpected" => true})
    assert {:error, {:unknown_field, :unexpected}} = Contract.new(%{unexpected: true})
  end

  test "rejects invalid contract shapes" do
    assert {:error, :invalid_contract} = Contract.new(:not_a_contract)

    assert {:error, {:invalid_field, :ownership, "unknown"}} =
             valid_attrs()
             |> Map.put(:ownership, "unknown")
             |> Contract.new()

    assert {:error, {:missing_fields, missing_fields}} = Contract.new(%{provider: "claude"})
    assert :backend in missing_fields
    assert :interactive_attach in missing_fields

    assert_raise ArgumentError, ~r/invalid provider runtime contract/, fn ->
      Contract.new!(%{provider: "claude"})
    end
  end

  defp valid_attrs do
    %{
      provider: "claude",
      backend: "direct_cli",
      ownership: "babs",
      status: "supported",
      command: %{"shape" => "claude --print --output-format json"},
      cwd_policy: %{"mode" => "resolved_cwd"},
      env_policy: %{"mode" => "allowlist"},
      launch_profiles: ["safe_interactive", "trusted_autonomous"],
      input_modes: ["argv_prompt"],
      resume: %{"supported" => true, "mode" => "provider_session_id"},
      session_id_parser: %{"supported" => true},
      reply_parser: %{"supported" => true},
      capabilities: %{"direct_turn" => true},
      version_fingerprint: %{"mode" => "deferred"},
      timeouts: %{"execution_ms" => 120_000},
      output_limits: %{"stdout_bytes" => 65_536, "stderr_bytes" => 65_536},
      diagnostics: %{"redacted" => true},
      raw_artifact_refs: [],
      interactive_attach: %{"supported" => false}
    }
  end
end
