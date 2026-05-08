defmodule Babs.Citizens.Tickets.MayorProposalTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.MayorProposal

  test "parses and normalizes whole-body JSON proposals" do
    assert {:ok, proposal} =
             MayorProposal.parse(Jason.encode!(valid_payload()),
               allowed_roles: ["developer", "inspector"],
               max_children: 5
             )

    assert proposal["proposal_id"] == "prop_20260508_demo"
    assert proposal["root_ticket_id"] == "T-2026-05-08-001"
    assert proposal["rules_refs_used"] == ["BAB-1503", "COR-1616"]
    assert proposal["risks"] == ["Requires focused validation."]
    assert proposal["questions"] == []

    assert [
             %{
               "title" => "Implement backend",
               "type" => "assignment",
               "priority" => "normal",
               "assignee_role" => "developer",
               "inspector" => "auto",
               "metadata" => %{
                 "inspection" => %{
                   "mode" => "auto",
                   "roles" => ["inspector"]
                 }
               }
             }
           ] = proposal["children"]
  end

  test "parses whole-body JSON when child body contains a Markdown code fence" do
    payload =
      valid_payload()
      |> put_in(["children", Access.at(0), "body"], """
      Use this example:

      ```json
      {"ok": true}
      ```
      """)

    assert {:ok, %{"children" => [%{"body" => body}]}} =
             MayorProposal.parse(Jason.encode!(payload),
               allowed_roles: ["developer", "inspector"]
             )

    assert body =~ "```json"
  end

  test "parses fenced JSON proposals and defaults human inspection children" do
    payload =
      valid_payload()
      |> put_in(["children"], [
        %{"title" => "Write docs", "body" => "Document the workflow.", "assignee_role" => nil}
      ])

    text = """
    Here is the proposal:

    ```json
    #{Jason.encode!(payload)}
    ```
    """

    assert {:ok, proposal} = MayorProposal.parse(text, allowed_roles: ["developer"])

    assert [%{"type" => "assignment", "priority" => "normal", "inspector" => "user"}] =
             proposal["children"]
  end

  test "parses fenced JSON when child body contains a Markdown code fence" do
    payload =
      valid_payload()
      |> put_in(["children", Access.at(0), "body"], """
      Return a fenced payload:

      ```json
      {"ok": true}
      ```
      """)

    text = """
    Here is the proposal:

    ```json
    #{Jason.encode!(payload)}
    ```
    """

    assert {:ok, %{"children" => [%{"body" => body}]}} =
             MayorProposal.parse(text, allowed_roles: ["developer", "inspector"])

    assert body =~ "```json"
  end

  test "accepts explicit compact inspector values that match derived inspection mode" do
    auto_payload =
      valid_payload()
      |> put_in(["children", Access.at(0), "inspector"], "auto")

    assert {:ok, %{"children" => [%{"inspector" => "auto"}]}} =
             MayorProposal.parse(Jason.encode!(auto_payload),
               allowed_roles: ["developer", "inspector"]
             )

    human_payload =
      valid_payload()
      |> put_in(["children"], [
        %{
          "title" => "Write docs",
          "body" => "Document the workflow.",
          "assignee_role" => nil,
          "inspector" => "human"
        }
      ])

    assert {:ok, %{"children" => [%{"inspector" => "user"}]}} =
             MayorProposal.parse(Jason.encode!(human_payload), allowed_roles: ["developer"])
  end

  test "rejects malformed proposals with stable reasons" do
    cases = [
      {Map.delete(valid_payload(), "proposal_id"), {:missing_field, "proposal_id"}},
      {Map.delete(valid_payload(), "root_ticket_id"), {:missing_field, "root_ticket_id"}},
      {Map.delete(valid_payload(), "summary"), {:missing_field, "summary"}},
      {Map.put(valid_payload(), "proposal_id", "bad id"), {:invalid_proposal_id, "bad id"}},
      {Map.delete(valid_payload(), "children"), {:missing_field, "children"}},
      {Map.put(valid_payload(), "children", []), :empty_children},
      {Map.delete(valid_payload(), "rules_refs_used"), {:missing_field, "rules_refs_used"}},
      {Map.delete(valid_payload(), "risks"), {:missing_field, "risks"}},
      {Map.delete(valid_payload(), "questions"), {:missing_field, "questions"}},
      {Map.put(valid_payload(), "risks", Enum.map(1..11, &"risk #{&1}")), {:too_many_risks, 11}},
      {put_in(valid_payload(), ["children"], [%{"title" => "", "body" => "Body"}]),
       {:invalid_child, 0, {:blank, "title"}}},
      {put_in(valid_payload(), ["children"], [
         %{"title" => "Bad", "body" => "Body", "assignee_role" => "designer"}
       ]), {:invalid_child, 0, {:disallowed_assignee_role, "designer"}}},
      {put_in(valid_payload(), ["children"], [
         %{"title" => "Bad", "body" => "Body", "inspector" => "auto"}
       ]), {:invalid_child, 0, {:conflicting_inspector, "auto"}}}
    ]

    for {payload, reason} <- cases do
      assert {:error, {:mayor_proposal, ^reason}} =
               MayorProposal.parse(Jason.encode!(payload),
                 allowed_roles: ["developer", "inspector"],
                 max_children: 5
               )
    end
  end

  test "rejects invalid child inspection metadata" do
    payload =
      put_in(valid_payload(), ["children"], [
        %{
          "title" => "Bad inspection",
          "body" => "Body",
          "assignee_role" => "developer",
          "metadata" => %{"inspection" => %{"mode" => "auto", "quorum" => "majority"}}
        }
      ])

    assert {:error,
            {:mayor_proposal,
             {:invalid_child, 0, {:inspection_policy, {:unsupported_quorum, "majority"}}}}} =
             MayorProposal.parse(Jason.encode!(payload),
               allowed_roles: ["developer", "inspector"],
               max_children: 5
             )
  end

  test "rejects invalid allowed role parser options" do
    assert {:error, {:mayor_proposal, {:invalid_allowed_roles, {:invalid_role_name, "bad/role"}}}} =
             MayorProposal.parse(Jason.encode!(valid_payload()), allowed_roles: ["bad/role"])
  end

  defp valid_payload do
    %{
      "proposal_id" => "prop_20260508_demo",
      "root_ticket_id" => "T-2026-05-08-001",
      "summary" => "Split into backend and validation.",
      "rules_refs_used" => [" BAB-1503 ", "COR-1616", "BAB-1503"],
      "children" => [
        %{
          "title" => "Implement backend",
          "body" => "Build the policy and schema first.",
          "assignee_role" => "Developer",
          "metadata" => %{"inspection" => %{"mode" => "auto", "roles" => ["Inspector"]}}
        }
      ],
      "risks" => ["Requires focused validation."],
      "questions" => []
    }
  end
end
