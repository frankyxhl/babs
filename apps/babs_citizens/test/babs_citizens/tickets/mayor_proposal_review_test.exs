defmodule Babs.Citizens.Tickets.MayorProposalReviewTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.MayorProposalReview
  alias Babs.Citizens.Tickets.Ticket

  @ticket_id "T-2026-05-08-061"

  test "reduces pending revised approved and rejected proposal states" do
    ticket = ticket()
    first = proposal("prop_first", ["Build backend", "Build frontend"])
    second = proposal("prop_second", ["Write docs"])

    assert {:ok, awaiting} = MayorProposalReview.from_history(ticket, [])
    assert awaiting.status == :awaiting

    assert {:ok, pending} =
             MayorProposalReview.from_history(ticket, [
               received(first, by: "flora")
             ])

    assert pending.status == :pending
    assert pending.proposal_id == "prop_first"
    assert is_binary(pending.revision_token)

    assert Enum.map(pending.proposal["children"], & &1["title"]) == [
             "Build backend",
             "Build frontend"
           ]

    assert {:ok, pending_second} =
             MayorProposalReview.from_history(ticket, [
               received(first, by: "flora"),
               revised(second, action: "edit_child", child_index: 0)
             ])

    assert pending_second.status == :pending
    assert pending_second.proposal_id == "prop_second"

    assert {:ok, approved} =
             MayorProposalReview.from_history(ticket, [
               received(second, by: "flora"),
               approved(second)
             ])

    assert approved.status == :approved
    assert approved.decision["event"] == "mayor_proposal_approved"

    assert {:ok, rejected} =
             MayorProposalReview.from_history(ticket, [
               received(second, by: "flora"),
               rejected(second, "Too broad.")
             ])

    assert rejected.status == :rejected
    assert rejected.feedback == "Too broad."
  end

  test "renders missing policy as missing and corrupt proposal events as controlled errors" do
    assert :missing = MayorProposalReview.from_history(%{ticket() | metadata: %{}}, [])

    assert {:error, {:mayor_proposal_review, {:invalid_proposal, {:missing_proposal, _event}}}} =
             MayorProposalReview.from_history(ticket(), [
               %{
                 "ts" => "2026-05-08T00:01:00Z",
                 "event" => "mayor_proposal_received",
                 "by" => "flora",
                 "ticket_id" => @ticket_id,
                 "proposal_id" => "prop_bad"
               }
             ])

    assert {:error,
            {:mayor_proposal_review,
             {:invalid_proposal, {:proposal_id_mismatch, "prop_bad", "prop_good"}}}} =
             MayorProposalReview.from_history(ticket(), [
               received(proposal("prop_good", ["Build"]), proposal_id: "prop_bad")
             ])
  end

  test "constructs edit remove approve and reject events without persisting" do
    ticket = ticket()
    history = [received(proposal("prop_demo", ["Build backend", "Build frontend"]))]

    assert {:ok, event} =
             MayorProposalReview.revise_child(
               ticket,
               history,
               "prop_demo",
               0,
               %{title: "Build API", inspector: "auto"},
               now: "2026-05-08T00:02:00Z",
               by: "user"
             )

    assert event["event"] == "mayor_proposal_revised"
    assert event["action"] == "edit_child"
    assert event["child_index"] == 0
    assert event["proposal"]["children"] |> hd() |> Map.fetch!("title") == "Build API"

    assert event["proposal"]["children"] |> hd() |> get_in(["metadata", "inspection", "mode"]) ==
             "auto"

    assert event["proposal_id"] == event["proposal"]["proposal_id"]

    assert {:ok, removed} =
             MayorProposalReview.remove_child(ticket, history, "prop_demo", 1,
               now: "2026-05-08T00:03:00Z"
             )

    assert removed["event"] == "mayor_proposal_revised"
    assert removed["action"] == "remove_child"
    assert removed["child_index"] == 1
    assert length(removed["proposal"]["children"]) == 1

    assert {:ok, approval} =
             MayorProposalReview.approve(ticket, history, "prop_demo",
               now: "2026-05-08T00:04:00Z"
             )

    assert approval["event"] == "mayor_proposal_approved"
    assert approval["proposal"]["proposal_id"] == "prop_demo"

    assert {:ok, rejection} =
             MayorProposalReview.reject(ticket, history, "prop_demo", "Needs fewer children.",
               now: "2026-05-08T00:05:00Z"
             )

    assert rejection["event"] == "mayor_proposal_rejected"
    assert rejection["feedback"] == "Needs fewer children."
    assert rejection["proposal"]["proposal_id"] == "prop_demo"
  end

  test "rejects stale decided invalid and terminal proposal actions" do
    ticket = ticket()
    history = [received(proposal("prop_demo", ["Build backend"]))]

    assert {:error, {:mayor_proposal_review, {:stale_proposal_id, "prop_demo", "prop_old"}}} =
             MayorProposalReview.approve(ticket, history, "prop_old")

    assert {:ok, state_before_revision} = MayorProposalReview.from_history(ticket, history)

    revised_history =
      history ++
        [
          revised(proposal("prop_demo", ["Build backend", "Build frontend"]),
            action: "edit_child",
            child_index: 0
          )
        ]

    assert {:ok, state_after_revision} = MayorProposalReview.from_history(ticket, revised_history)

    assert {:error,
            {:mayor_proposal_review,
             {:stale_proposal_revision, current_revision, submitted_revision}}} =
             MayorProposalReview.revise_child(
               ticket,
               revised_history,
               "prop_demo",
               0,
               %{title: "Stale edit"},
               proposal_revision: state_before_revision.revision_token
             )

    assert current_revision == state_after_revision.revision_token
    assert submitted_revision == state_before_revision.revision_token

    assert {:error, {:mayor_proposal_review, {:invalid_child_index, 2}}} =
             MayorProposalReview.revise_child(ticket, history, "prop_demo", 2, %{title: "Nope"})

    assert {:error,
            {:mayor_proposal_review,
             {:invalid_edit, {:mayor_proposal, {:invalid_child, 0, {:blank, "title"}}}}}} =
             MayorProposalReview.revise_child(ticket, history, "prop_demo", 0, %{title: " "})

    assert {:error, {:mayor_proposal_review, {:invalid_edit, :empty_children}}} =
             MayorProposalReview.remove_child(ticket, history, "prop_demo", 0)

    assert {:error, {:mayor_proposal_review, :empty_feedback}} =
             MayorProposalReview.reject(ticket, history, "prop_demo", " ")

    decided_history = history ++ [approved(proposal("prop_demo", ["Build backend"]))]

    assert {:error, {:mayor_proposal_review, {:already_decided, :approved}}} =
             MayorProposalReview.remove_child(ticket, decided_history, "prop_demo", 0)

    assert {:error, {:mayor_proposal_review, {:terminal_ticket, @ticket_id, "closed"}}} =
             MayorProposalReview.approve(%{ticket | state: "closed"}, history, "prop_demo")
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
          "rules_refs" => ["BAB-1503", "COR-1616"],
          "max_children" => 5,
          "allowed_roles" => ["developer", "inspector"],
          "require_human_approval" => true
        }
      },
      title: "Root mission",
      body: "Coordinate the work.",
      path: nil,
      warnings: []
    }
  end

  defp proposal(proposal_id, titles) do
    %{
      "proposal_id" => proposal_id,
      "root_ticket_id" => @ticket_id,
      "summary" => "Split the work.",
      "rules_refs_used" => ["BAB-1503"],
      "children" =>
        Enum.map(titles, fn title ->
          %{
            "title" => title,
            "body" => "Complete #{title}.",
            "type" => "assignment",
            "priority" => "normal",
            "assignee_role" => "developer",
            "inspector" => "user",
            "metadata" => %{}
          }
        end),
      "risks" => ["Keep slices small."],
      "questions" => []
    }
  end

  defp received(proposal, opts \\ []) do
    %{
      "ts" => "2026-05-08T00:01:00Z",
      "event" => "mayor_proposal_received",
      "by" => Keyword.get(opts, :by, "flora"),
      "ticket_id" => @ticket_id,
      "proposal_id" => Keyword.get(opts, :proposal_id, proposal["proposal_id"]),
      "proposal" => proposal
    }
  end

  defp revised(proposal, opts) do
    %{
      "ts" => "2026-05-08T00:02:00Z",
      "event" => "mayor_proposal_revised",
      "by" => "user",
      "ticket_id" => @ticket_id,
      "proposal_id" => proposal["proposal_id"],
      "action" => Keyword.fetch!(opts, :action),
      "child_index" => Keyword.fetch!(opts, :child_index),
      "proposal" => proposal
    }
  end

  defp approved(proposal) do
    %{
      "ts" => "2026-05-08T00:03:00Z",
      "event" => "mayor_proposal_approved",
      "by" => "user",
      "ticket_id" => @ticket_id,
      "proposal_id" => proposal["proposal_id"],
      "proposal" => proposal
    }
  end

  defp rejected(proposal, feedback) do
    %{
      "ts" => "2026-05-08T00:03:00Z",
      "event" => "mayor_proposal_rejected",
      "by" => "user",
      "ticket_id" => @ticket_id,
      "proposal_id" => proposal["proposal_id"],
      "feedback" => feedback,
      "proposal" => proposal
    }
  end
end
