defmodule Babs.Citizens.Tickets.InspectionRequestTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.Tickets.Api

  setup do
    config_root = tmp_root!()
    tickets_root = tmp_root!()

    on_exit(fn ->
      File.rm_rf!(config_root)
      File.rm_rf!(tickets_root)
    end)

    {:ok, config_root: config_root, tickets_root: tickets_root}
  end

  test "request_inspection appends request before prompt delivery without changing state", ctx do
    write_citizen_toml!(ctx.config_root, "dylan")

    insert_citizen!(%{
      slug: "dylan",
      roles: ["inspector"],
      env: %{"BAB_TEST_VALUE" => "should-not-return"},
      metadata: %{"hardline" => %{"tmux" => %{"session" => "private-pane"}}}
    })

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Ready for inspection",
                 body: "Review the completed work.",
                 state: "pending_approval",
                 assignees: ["clare"],
                 metadata: %{
                   "inspection" => %{
                     "mode" => "auto",
                     "roles" => ["inspector"],
                     "citizens" => ["dylan"],
                     "max_inspectors" => 1
                   }
                 }
               },
               tickets_root: ctx.tickets_root,
               date: ~D[2026-05-08],
               now: "2026-05-08T10:00:00Z"
             )

    assert {:ok, result} =
             Api.request_inspection(ticket.id,
               root: ctx.config_root,
               tickets_root: ctx.tickets_root,
               now: "2026-05-08T10:01:00Z",
               inspection_id: "insp_20260508100100_42"
             )

    assert result.inspection_id == "insp_20260508100100_42"
    assert Enum.map(result.inspectors, & &1.slug) == ["dylan"]
    refute Map.has_key?(hd(result.inspectors), :citizen)

    assert [%{to: "dylan", prompt: prompt, turn_id: turn_id, attempt_id: attempt_id}] =
             result.prompts

    assert prompt =~ "You are dylan, a Babs Inspector Citizen."
    assert prompt =~ "Ready for inspection"
    assert turn_id =~ ~r/\Aturn_20260508100100_[a-z0-9]{10}\z/
    assert attempt_id =~ ~r/\Aattempt_20260508100100_[a-z0-9]{10}\z/

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)

    assert shown.state == "pending_approval"

    assert ["created", "inspection_requested", "inspection_prompt_delivered"] =
             Enum.map(history, & &1["event"])

    assert Enum.at(history, 1)["inspectors"] == ["dylan"]
    assert Enum.at(history, 2)["to"] == "dylan"
    assert Enum.at(history, 2)["inspection_id"] == "insp_20260508100100_42"
  end

  test "request_inspection keeps human policy on the human approval path", ctx do
    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Human approval",
                 body: "This should not auto-inspect.",
                 state: "pending_approval",
                 assignees: ["clare"],
                 metadata: %{"inspection" => %{"mode" => "human"}}
               },
               tickets_root: ctx.tickets_root,
               date: ~D[2026-05-08],
               now: "2026-05-08T10:00:00Z"
             )

    assert {:error, {:inspection_not_auto, "human"}} =
             Api.request_inspection(ticket.id,
               root: ctx.config_root,
               tickets_root: ctx.tickets_root,
               now: "2026-05-08T10:01:00Z"
             )

    assert {:ok, %{history: [%{"event" => "created"}]}} =
             Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
  end

  test "request_inspection requires pending approval before recording events", ctx do
    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Still running",
                 body: "This ticket is not ready for inspection.",
                 state: "in_progress",
                 assignees: ["clare"],
                 metadata: %{
                   "inspection" => %{
                     "mode" => "auto",
                     "roles" => ["inspector"]
                   }
                 }
               },
               tickets_root: ctx.tickets_root,
               date: ~D[2026-05-08],
               now: "2026-05-08T10:00:00Z"
             )

    assert {:error,
            {:inspection_requires_human,
             {:not_pending_approval, "T-2026-05-08-001", "in_progress"}}} =
             Api.request_inspection(ticket.id,
               root: ctx.config_root,
               tickets_root: ctx.tickets_root,
               now: "2026-05-08T10:01:00Z"
             )

    assert {:ok, %{history: [%{"event" => "created"}]}} =
             Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
  end
end
