defmodule Babs.Citizens.Tickets.InspectionEventsTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.InspectionEvents

  @id "T-2026-05-08-001"
  @inspection_id "insp_20260508000000_42"
  @now "2026-05-08T00:00:00Z"
  @policy %{
    "mode" => "auto",
    "strategy" => "single",
    "roles" => ["inspector"],
    "citizens" => [],
    "quorum" => "all_pass",
    "max_inspectors" => 3,
    "allow_self_inspection" => false
  }

  test "generates stable log-safe inspection ids" do
    assert InspectionEvents.new_id(@now, unique: 42) == @inspection_id
    assert InspectionEvents.new_id(@now, unique: 43) =~ ~r/^insp_20260508000000_\d+$/
  end

  test "builds appendable inspection_requested events" do
    assert {:ok, event} =
             InspectionEvents.requested(@id, @inspection_id, @policy, ["clare"], now: @now)

    assert event["event"] == "inspection_requested"
    assert event["ticket_id"] == @id
    assert event["inspection_id"] == @inspection_id
    assert event["policy"] == @policy
    assert event["inspectors"] == ["clare"]
    assert :ok = History.validate_appendable(@id, event)
    assert {:ok, _json} = Jason.encode(event)
  end

  test "builds appendable prompt-delivered constructor events without delivery side effects" do
    assert {:ok, event} =
             InspectionEvents.prompt_delivered(
               @id,
               @inspection_id,
               "clare",
               "turn_1",
               "attempt_1",
               now: @now
             )

    assert event["event"] == "inspection_prompt_delivered"
    assert event["to"] == "clare"
    assert event["turn_id"] == "turn_1"
    assert event["attempt_id"] == "attempt_1"
    assert :ok = History.validate_appendable(@id, event)
  end

  test "builds appendable decision events for allowed verdicts" do
    for decision <- ["approve", "reject", "needs_changes"] do
      assert {:ok, event} =
               InspectionEvents.decision(
                 @id,
                 @inspection_id,
                 "clare",
                 decision,
                 "Checked acceptance criteria.",
                 [%{"severity" => "info", "body" => "Looks consistent."}],
                 now: @now
               )

      assert event["event"] == "inspection_decision"
      assert event["decision"] == decision
      assert event["summary"] == "Checked acceptance criteria."
      assert is_list(event["findings"])
      assert :ok = History.validate_appendable(@id, event)
    end
  end

  test "rejects invalid decision values" do
    assert {:error, {:invalid_inspection_decision, "maybe"}} =
             InspectionEvents.decision(@id, @inspection_id, "clare", "maybe", "Nope.", [],
               now: @now
             )
  end

  test "rejects malformed decision payloads" do
    assert {:error, :invalid_summary} =
             InspectionEvents.decision(@id, @inspection_id, "clare", "approve", "", [], now: @now)

    assert {:error, {:invalid_findings, ["not-a-map"]}} =
             InspectionEvents.decision(
               @id,
               @inspection_id,
               "clare",
               "approve",
               "Summary.",
               ["not-a-map"],
               now: @now
             )
  end

  test "rejects malformed inspection ids" do
    assert {:error, {:invalid_inspection_id, "inspection-1"}} =
             InspectionEvents.requested(@id, "inspection-1", @policy, ["clare"], now: @now)
  end

  test "rejects malformed constructor routing fields" do
    assert {:error, :invalid_inspectors} =
             InspectionEvents.requested(@id, @inspection_id, @policy, ["clare", 1], now: @now)

    assert {:error, :invalid_inspector} =
             InspectionEvents.prompt_delivered(@id, @inspection_id, "", "turn_1", "attempt_1",
               now: @now
             )

    assert {:error, :invalid_turn_id} =
             InspectionEvents.prompt_delivered(@id, @inspection_id, "clare", "", "attempt_1",
               now: @now
             )

    assert {:error, :invalid_attempt_id} =
             InspectionEvents.prompt_delivered(@id, @inspection_id, "clare", "turn_1", "",
               now: @now
             )
  end

  test "builds appendable inspection_failed events with normalized error text" do
    assert {:ok, event} =
             InspectionEvents.failed(@id, @inspection_id, "dylan", {:timeout, :provider},
               now: @now
             )

    assert event["event"] == "inspection_failed"
    assert event["to"] == "dylan"
    assert is_binary(event["error"])
    refute event["error"] =~ "raw-sensitive-marker"
    assert :ok = History.validate_appendable(@id, event)
  end

  test "builds appendable completed events for allowed results" do
    for result <- ["approved", "rejected", "requires_human"] do
      assert {:ok, event} =
               InspectionEvents.completed(@id, @inspection_id, result, "all_pass", now: @now)

      assert event["event"] == "inspection_completed"
      assert event["result"] == result
      assert event["quorum"] == "all_pass"
      assert :ok = History.validate_appendable(@id, event)
    end
  end

  test "rejects invalid completed results and quorum" do
    assert {:error, {:invalid_inspection_result, "maybe"}} =
             InspectionEvents.completed(@id, @inspection_id, "maybe", "all_pass", now: @now)

    assert {:error, {:unsupported_quorum, "majority"}} =
             InspectionEvents.completed(@id, @inspection_id, "approved", "majority", now: @now)
  end

  test "validate_appendable rejects incomplete event maps" do
    assert {:error, {:invalid_history_event, {:missing_keys, ["by"]}}} =
             History.validate_appendable(@id, %{
               "ts" => @now,
               "event" => "inspection_requested"
             })
  end
end
