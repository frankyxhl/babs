defmodule Babs.Citizens.Tickets.StateMachineTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.StateMachine
  alias Babs.Citizens.Tickets.Ticket

  test "assign moves an open billboard ticket to in_progress for one citizen" do
    ticket = ticket()

    assert {:ok, updated} = StateMachine.assign(ticket, "clare")
    assert updated.state == "in_progress"
    assert updated.assignees == ["clare"]
  end

  test "assign rejects invalid citizen slugs and already assigned tickets" do
    assert {:error, {:invalid_slug, ""}} = StateMachine.assign(ticket(), "")
    assert {:error, {:invalid_slug, "Bad Slug"}} = StateMachine.assign(ticket(), "Bad Slug")

    assert {:error, {:invalid_transition, "in_progress", "in_progress"}} =
             ticket(state: "in_progress", assignees: ["clare"])
             |> StateMachine.assign("dylan")
  end

  test "unassigning the last assignee returns the ticket to the billboard" do
    ticket = ticket(state: "in_progress", assignees: ["clare"])

    assert {:ok, updated} = StateMachine.unassign(ticket, "clare")
    assert updated.state == "open"
    assert updated.assignees == []
  end

  test "rejects direct unassign from pending_approval" do
    ticket = ticket(state: "pending_approval", assignees: ["clare"])

    assert {:error, {:invalid_transition, "pending_approval", "open"}} =
             StateMachine.unassign(ticket, "clare")
  end

  test "unassign rejects invalid citizen slugs before changing assignment" do
    ticket = ticket(state: "in_progress", assignees: ["clare"])

    assert {:error, {:invalid_slug, ""}} = StateMachine.unassign(ticket, "")
  end

  test "accepts approved legal state transitions" do
    assert {:ok, pending, "state_change"} =
             ticket(state: "in_progress", assignees: ["clare"])
             |> StateMachine.transition("pending_approval", nil)

    assert pending.state == "pending_approval"

    assert {:ok, closed, "state_change"} = StateMachine.transition(pending, "closed", nil)
    assert closed.state == "closed"

    assert {:ok, approved, "approved"} = StateMachine.transition(pending, "closed", "approved")
    assert approved.state == "closed"

    assert {:ok, rejected, "rejected"} =
             StateMachine.transition(pending, "in_progress", "rejected")

    assert rejected.state == "in_progress"
  end

  test "rejects illegal state transitions" do
    assert {:error, {:invalid_transition, "open", "closed"}} =
             ticket()
             |> StateMachine.transition("closed", nil)

    assert {:error, {:invalid_transition, "closed", "open"}} =
             ticket(state: "closed", assignees: ["clare"])
             |> StateMachine.transition("open", nil)

    assert {:error, {:invalid_transition_event, "accepted", "approved"}} =
             ticket(state: "pending_approval", assignees: ["clare"])
             |> StateMachine.transition("closed", "accepted")
  end

  defp ticket(attrs \\ []) do
    defaults = %{
      id: "T-2026-05-06-001",
      type: "assignment",
      state: "open",
      assigner: "user",
      assignees: [],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-06T00:00:00Z",
      updated_at: "2026-05-06T00:00:00Z",
      metadata: %{},
      title: "State machine",
      body: "Move through legal states.",
      path: "/tmp/T-2026-05-06-001.md",
      warnings: []
    }

    struct!(Ticket, Map.merge(defaults, Map.new(attrs)))
  end
end
