defmodule Babs.Citizens.ProviderRuntime.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.ProviderRuntime.Diagnostics

  test "normalizes timeout diagnostics" do
    assert Diagnostics.failure(:timeout) == %{
             redacted: true,
             summary: "provider execution timed out",
             category: "timeout",
             raw_included: false
           }

    assert Diagnostics.status(:timeout) == :timeout
    assert Diagnostics.category(:timeout) == "timeout"
  end

  test "summarizes exit status without raw stdout or stderr" do
    diagnostics =
      Diagnostics.failure(
        {:exit_status, 2,
         %{
           stdout: "raw provider stdout with /Users/alice/secret",
           stderr: "provider stderr api_token=secret"
         }}
      )

    assert diagnostics.category == "failed"
    assert diagnostics.summary == "provider exited with status 2"
    refute inspect(diagnostics) =~ "raw provider stdout"
    refute inspect(diagnostics) =~ "api_token=secret"
    refute inspect(diagnostics) =~ "/Users/alice"
  end

  test "redacts fallback summaries with configured secret values" do
    diagnostics =
      Diagnostics.failure(
        {:bad_provider_reply,
         "printed sk-test-secret-value at /home/operator/work and 100.64.0.1"},
        secret_values: ["sk-test-secret-value"]
      )

    assert diagnostics.category == "failed"
    assert diagnostics.summary =~ "[REDACTED]"
    refute diagnostics.summary =~ "sk-test-secret-value"
    refute diagnostics.summary =~ "/home/operator"
    refute diagnostics.summary =~ "100.64.0.1"
  end

  test "redacts and bounds long fallback summaries" do
    secret = "sk-test-secret-value"
    long_output = secret <> String.duplicate("a", 3_000)

    diagnostics =
      Diagnostics.failure({:bad_provider_reply, long_output}, secret_values: [secret])

    assert diagnostics.summary =~ "[REDACTED]"
    refute diagnostics.summary =~ secret
    assert byte_size(diagnostics.summary) <= 2_012
  end

  test "classifies unsupported and cancelled diagnostics" do
    assert Diagnostics.status({:unsupported_direct_cli, "zsh"}) == :unsupported
    assert Diagnostics.failure({:unsupported_direct_cli, "zsh"}).category == "unsupported"

    assert Diagnostics.status(:cancelled) == :cancelled
    assert Diagnostics.failure(:cancelled).category == "cancelled"
  end
end
