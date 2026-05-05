defmodule Babs.Citizens.GateA.ValidatorTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.GateA.Validator

  @repo_root Path.expand("../../../../..", __DIR__)

  test "detects stable tmux metadata" do
    assert :ok = Validator.verify_stable_metadata({"$1", 123}, {"$1", 123})
  end

  test "rejects changed session id and pane pid" do
    assert {:error, {:session_id_changed, "$1", "$2"}} =
             Validator.verify_stable_metadata({"$1", 123}, {"$2", 123})

    assert {:error, {:pane_pid_changed, 123, 456}} =
             Validator.verify_stable_metadata({"$1", 123}, {"$1", 456})
  end

  test "matches markers inside captured tmux output" do
    assert Validator.capture_contains?("before\nBABS_MARKER\nafter", "BABS_MARKER")
    refute Validator.capture_contains?("before\nafter", "BABS_MARKER")
  end

  test "creates unique marker strings with the requested prefix" do
    first = Validator.marker("BEFORE")
    second = Validator.marker("BEFORE")

    assert String.starts_with?(first, "BEFORE_")
    assert first != second
  end

  test "runs the scripted sentinel validation" do
    assert {:ok, result} = Validator.run(root: @repo_root)
    assert result.session == "babs-sentinel"
    assert is_binary(result.session_id)
    assert is_integer(result.pane_pid)
  end

  test "reports sentinel load errors" do
    root =
      Path.join(System.tmp_dir!(), "babs-gate-a-missing-#{System.unique_integer([:positive])}")

    assert {:error, {:load_sentinel_failed, _reason}} = Validator.run(root: root)
  end
end
