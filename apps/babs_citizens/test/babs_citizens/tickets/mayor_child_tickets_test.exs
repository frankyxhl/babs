defmodule Babs.Citizens.Tickets.MayorChildTicketsTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.MayorChildTickets
  alias Babs.Citizens.Tickets.MayorProposalReview
  alias Babs.Citizens.Tickets.Ticket

  @ticket_id "T-2026-05-08-064"

  test "builds child ticket attrs from a pending mayor proposal" do
    proposal =
      proposal("prop_children", [
        %{
          "title" => "Build backend",
          "body" => "Implement the backend slice.",
          "priority" => "high",
          "assignee_role" => "developer",
          "inspector" => "auto",
          "metadata" => %{"inspection" => %{"mode" => "auto", "roles" => ["inspector"]}}
        }
      ])

    assert {:ok, state} = MayorProposalReview.from_history(ticket(), [received(proposal)])
    assert {:ok, plan} = MayorChildTickets.plan(ticket(), state)

    assert plan.proposal_id == "prop_children"
    assert plan.assigner == "mayor:flora"
    assert [child] = plan.children
    assert child.child_index == 0
    assert child.route? == true

    assert child.attrs == %{
             title: "Build backend",
             body: "Implement the backend slice.",
             type: "assignment",
             state: "open",
             assigner: "mayor:flora",
             assignees: [],
             assignee_role: "developer",
             inspector: "auto",
             priority: "high",
             parent_ticket: @ticket_id,
             metadata: %{
               "inspection" => %{
                 "allow_self_inspection" => false,
                 "citizens" => [],
                 "max_inspectors" => 3,
                 "mode" => "auto",
                 "quorum" => "all_pass",
                 "roles" => ["inspector"],
                 "strategy" => "single"
               }
             }
           }
  end

  test "uses generic mayor provenance and skips role routing without an assignee role" do
    root = %{ticket() | metadata: put_in(ticket().metadata, ["mayor", "mayor"], nil)}
    proposal = proposal("prop_any", [%{"title" => "Write notes", "assignee_role" => nil}])

    assert {:ok, state} = MayorProposalReview.from_history(root, [received(proposal)])
    assert {:ok, plan} = MayorChildTickets.plan(root, state)

    assert plan.assigner == "mayor"
    assert [child] = plan.children
    assert child.route? == false
    assert child.attrs.assigner == "mayor"
    assert child.attrs.assignee_role == nil
  end

  test "builds compact children-created event without embedding child bodies" do
    proposal = proposal("prop_event", [%{"title" => "Build backend"}])
    assert {:ok, state} = MayorProposalReview.from_history(ticket(), [received(proposal)])
    assert {:ok, plan} = MayorChildTickets.plan(ticket(), state)

    children = [
      %{
        child_index: 0,
        ticket_id: "T-2026-05-08-065",
        title: "Build backend",
        priority: "normal",
        inspector: "user",
        assignee_role: "developer",
        routing: %{
          "status" => "failed",
          "reason" => "No eligible Citizen found for role developer"
        }
      }
    ]

    event =
      MayorChildTickets.children_created_event(ticket(), plan, children,
        now: "2026-05-08T00:02:00Z",
        by: "user"
      )

    assert event["event"] == "mayor_children_created"
    assert event["proposal_id"] == "prop_event"

    assert event["children"] == [
             %{
               "child_index" => 0,
               "ticket_id" => "T-2026-05-08-065",
               "title" => "Build backend",
               "priority" => "normal",
               "inspector" => "user",
               "assignee_role" => "developer",
               "routing" => %{
                 "status" => "failed",
                 "reason" => "No eligible Citizen found for role developer"
               }
             }
           ]

    refute inspect(event) =~ "Complete Build backend"
  end

  defp ticket do
    %Ticket{
      id: @ticket_id,
      type: "mission",
      state: "open",
      assigner: "user",
      assignees: [],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-08T00:00:00Z",
      updated_at: "2026-05-08T00:00:00Z",
      metadata: %{
        "mayor" => %{
          "mode" => "propose",
          "mayor" => "flora",
          "rules_refs" => ["BAB-1503"],
          "max_children" => 5,
          "allowed_roles" => ["developer", "inspector"],
          "require_human_approval" => true
        }
      },
      title: "Root mission",
      body: "Coordinate work.",
      path: nil,
      warnings: []
    }
  end

  defp proposal(proposal_id, children) do
    %{
      "proposal_id" => proposal_id,
      "root_ticket_id" => @ticket_id,
      "summary" => "Split the work.",
      "rules_refs_used" => ["BAB-1503"],
      "children" =>
        Enum.map(children, fn child ->
          title = Map.get(child, "title", "Build child")

          %{
            "title" => title,
            "body" => Map.get(child, "body", "Complete #{title}."),
            "type" => Map.get(child, "type", "assignment"),
            "priority" => Map.get(child, "priority", "normal"),
            "assignee_role" => Map.get(child, "assignee_role", "developer"),
            "inspector" => Map.get(child, "inspector", "user"),
            "metadata" => Map.get(child, "metadata", %{})
          }
        end),
      "risks" => [],
      "questions" => []
    }
  end

  defp received(proposal) do
    %{
      "ts" => "2026-05-08T00:01:00Z",
      "event" => "mayor_proposal_received",
      "by" => "flora",
      "ticket_id" => @ticket_id,
      "proposal_id" => proposal["proposal_id"],
      "proposal" => proposal
    }
  end
end
