defmodule Babs.Citizens.Tickets.InspectionQuorumTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.InspectionQuorum

  @inspection_id "insp_20260508120000_1"

  test "approves when all selected inspectors approve" do
    history =
      requested(["clare", "dylan"]) ++
        [decision("clare", "approve"), decision("dylan", "approve")]

    assert {:ok, {:approved, result}} = InspectionQuorum.reduce(history, @inspection_id)
    assert result.inspectors == ["clare", "dylan"]
  end

  test "rejects immediately when any inspector rejects" do
    history = requested(["clare", "dylan"]) ++ [decision("clare", "reject", "Missing docs.")]

    assert {:ok, {:rejected, result}} = InspectionQuorum.reduce(history, @inspection_id)
    assert result.result == "rejected"
    assert result.feedback =~ "clare reject: Missing docs."
  end

  test "maps needs_changes to rejected result while preserving decision value" do
    history = requested(["clare"]) ++ [decision("clare", "needs_changes", "Add a test.")]

    assert {:ok, {:rejected, result}} = InspectionQuorum.reduce(history, @inspection_id)
    assert result.result == "rejected"
    assert hd(result.decisions)["decision"] == "needs_changes"
  end

  test "requires human when an inspector decision failed to parse" do
    history = requested(["clare"]) ++ [failed("clare")]

    assert {:ok, {:requires_human, result}} = InspectionQuorum.reduce(history, @inspection_id)
    assert result.result == "requires_human"
    assert result.reason == "inspection_failed"
  end

  test "stays pending while selected inspectors are missing decisions" do
    history = requested(["clare", "dylan"]) ++ [decision("clare", "approve")]

    assert {:ok, :pending} = InspectionQuorum.reduce(history, @inspection_id)
  end

  test "rejects invalid requested events with no inspectors" do
    history = requested([])

    assert {:error, {:no_inspectors, @inspection_id}} =
             InspectionQuorum.reduce(history, @inspection_id)
  end

  test "tracks only the latest unresolved inspection as active" do
    newer_id = "insp_20260508120500_2"

    history =
      requested(["clare"]) ++
        [
          %{
            "ts" => "2026-05-08T12:05:00Z",
            "event" => "inspection_requested",
            "by" => "system",
            "ticket_id" => "T-2026-05-08-001",
            "inspection_id" => newer_id,
            "policy" => %{"quorum" => "all_pass"},
            "inspectors" => ["dylan"]
          }
        ]

    refute InspectionQuorum.active_inspection?(history, @inspection_id)
    assert InspectionQuorum.active_inspection?(history, newer_id)
    assert %{"inspection_id" => ^newer_id} = InspectionQuorum.active_request(history)
  end

  test "ignores already completed inspections" do
    history =
      requested(["clare"]) ++
        [completed("approved"), decision("clare", "reject", "Late feedback.")]

    assert InspectionQuorum.completed?(history, @inspection_id)
    assert {:ok, :completed} = InspectionQuorum.reduce(history, @inspection_id)
  end

  test "treats human override transition as resolving the active request" do
    history =
      requested(["clare"]) ++
        [
          %{
            "ts" => "2026-05-08T12:02:00Z",
            "event" => "rejected",
            "by" => "user",
            "ticket_id" => "T-2026-05-08-001",
            "from" => "pending_approval",
            "to" => "in_progress",
            "feedback" => "Needs another pass."
          },
          %{
            "ts" => "2026-05-08T12:02:00Z",
            "event" => "state_change",
            "by" => "user",
            "ticket_id" => "T-2026-05-08-001",
            "from" => "pending_approval",
            "to" => "in_progress"
          }
        ]

    refute InspectionQuorum.active_inspection?(history, @inspection_id)
    assert InspectionQuorum.active_request(history) == nil
  end

  test "does not reactivate older requests after the latest request resolves" do
    newer_id = "insp_20260508120500_2"

    history =
      requested(["clare"]) ++
        [
          %{
            "ts" => "2026-05-08T12:05:00Z",
            "event" => "inspection_requested",
            "by" => "system",
            "ticket_id" => "T-2026-05-08-001",
            "inspection_id" => newer_id,
            "policy" => %{"quorum" => "all_pass"},
            "inspectors" => ["dylan"]
          },
          %{
            "ts" => "2026-05-08T12:06:00Z",
            "event" => "inspection_completed",
            "by" => "system",
            "ticket_id" => "T-2026-05-08-001",
            "inspection_id" => newer_id,
            "result" => "requires_human",
            "quorum" => "all_pass"
          }
        ]

    refute InspectionQuorum.active_inspection?(history, @inspection_id)
    refute InspectionQuorum.active_inspection?(history, newer_id)
    assert InspectionQuorum.active_request(history) == nil
  end

  defp requested(inspectors) do
    [
      %{
        "ts" => "2026-05-08T12:00:00Z",
        "event" => "inspection_requested",
        "by" => "system",
        "ticket_id" => "T-2026-05-08-001",
        "inspection_id" => @inspection_id,
        "policy" => %{"quorum" => "all_pass"},
        "inspectors" => inspectors
      }
    ]
  end

  defp decision(by, decision, summary \\ "Looks good.") do
    %{
      "ts" => "2026-05-08T12:01:00Z",
      "event" => "inspection_decision",
      "by" => by,
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => @inspection_id,
      "decision" => decision,
      "summary" => summary,
      "findings" => []
    }
  end

  defp failed(to) do
    %{
      "ts" => "2026-05-08T12:01:00Z",
      "event" => "inspection_failed",
      "by" => "system",
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => @inspection_id,
      "to" => to,
      "error" => "Inspection failed: unparseable decision"
    }
  end

  defp completed(result) do
    %{
      "ts" => "2026-05-08T12:02:00Z",
      "event" => "inspection_completed",
      "by" => "system",
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => @inspection_id,
      "result" => result,
      "quorum" => "all_pass"
    }
  end
end
