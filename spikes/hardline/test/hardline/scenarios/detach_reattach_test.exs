defmodule Hardline.Scenarios.DetachReattachTest do
  use ExUnit.Case, async: true

  alias Hardline.Scenarios.DetachReattach

  test "passes when tmux session, workload pid, and byte sequence survive" do
    before_snapshot = %{
      session_id: "session-a",
      workload_pid: 123,
      sequence: 10
    }

    after_snapshot = %{
      session_id: "session-a",
      workload_pid: 123,
      sequence: 11
    }

    assert :ok = DetachReattach.validate_snapshots(before_snapshot, after_snapshot)
  end

  test "fails when tmux session changes" do
    assert {:error, :session_changed} =
             DetachReattach.validate_snapshots(
               %{session_id: "old", workload_pid: 123, sequence: 10},
               %{session_id: "new", workload_pid: 123, sequence: 11}
             )
  end

  test "fails when workload pid changes" do
    assert {:error, :workload_pid_changed} =
             DetachReattach.validate_snapshots(
               %{session_id: "same", workload_pid: 123, sequence: 10},
               %{session_id: "same", workload_pid: 456, sequence: 11}
             )
  end

  test "fails when the observed sequence skips bytes" do
    assert {:error, :sequence_gap} =
             DetachReattach.validate_snapshots(
               %{session_id: "same", workload_pid: 123, sequence: 10},
               %{session_id: "same", workload_pid: 123, sequence: 12}
             )
  end
end
