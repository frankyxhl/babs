defmodule Babs.Citizens.ProviderRuntime.ResultTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.ProviderRuntime.Result

  test "builds a normalized direct CLI success result with legacy text alias" do
    result =
      Result.direct_success("codex", "codex reply",
        provider_session_id: "codex-thread",
        capabilities: %{"direct" => true, "resume" => true}
      )

    assert result.status == :ok
    assert result.provider == "codex"
    assert result.backend == "direct_cli"
    assert result.provider_session_id == "codex-thread"
    assert result.reply == "codex reply"
    assert result.text == "codex reply"
    assert result.capabilities == %{"direct" => true, "resume" => true}
    assert result.diagnostics == %{redacted: true, summary: nil}
    assert result.raw_artifact_refs == []
  end

  test "defaults direct CLI capabilities when none are provided" do
    result = Result.direct_success("fake", "ok")

    assert result.capabilities == %{"direct" => true}
    assert result.diagnostics == %{redacted: true, summary: nil}
    assert result.raw_artifact_refs == []
  end
end
