defmodule Babs.Citizens.Tickets.InspectionDecisionCaptureTest do
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

  test "matching approve reply closes a single-inspector pending approval ticket", ctx do
    %{ticket: ticket, prompt: prompt} = request_inspection!(ctx, ["dylan"])

    assert {:ok, %{ticket: closed}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("dylan", prompt, "approve", "Acceptance criteria are met."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z"
             )

    assert closed.state == "closed"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
    events = Enum.map(history, & &1["event"])

    assert "inspection_decision" in events
    assert "inspection_completed" in events
    assert Enum.take(events, -3) == ["inspection_completed", "approved", "state_change"]

    approved_event = Enum.find(history, &(&1["event"] == "approved"))
    state_change_event = history |> Enum.reverse() |> Enum.find(&(&1["event"] == "state_change"))

    assert approved_event["inspection_id"] == "insp_20260508120100_1"
    assert state_change_event["inspection_id"] == "insp_20260508120100_1"
  end

  test "reject reply returns the ticket to in progress with feedback", ctx do
    parent = self()
    %{ticket: ticket, prompt: prompt} = request_inspection!(ctx, ["dylan"])

    assert {:ok, %{ticket: rejected}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("dylan", prompt, "reject", "Documentation is missing."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", feedback ->
                 send(parent, {:feedback, feedback})
                 :ok
               end
             )

    assert rejected.state == "in_progress"
    assert_receive {:feedback, feedback}
    assert feedback =~ "dylan reject: Documentation is missing."

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
    completed = Enum.find(history, &(&1["event"] == "inspection_completed"))
    rejected_event = Enum.find(history, &(&1["event"] == "rejected"))
    state_change_event = history |> Enum.reverse() |> Enum.find(&(&1["event"] == "state_change"))

    assert completed["result"] == "rejected"
    assert rejected_event["inspection_id"] == "insp_20260508120100_1"
    assert rejected_event["feedback"] =~ "Documentation is missing."
    assert state_change_event["inspection_id"] == "insp_20260508120100_1"
  end

  test "needs_changes reply returns the ticket to in progress with feedback", ctx do
    parent = self()
    %{ticket: ticket, prompt: prompt} = request_inspection!(ctx, ["dylan"])

    assert {:ok, %{ticket: rejected}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("dylan", prompt, "needs_changes", "Add one regression test."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", feedback ->
                 send(parent, {:feedback, feedback})
                 :ok
               end
             )

    assert rejected.state == "in_progress"
    assert_receive {:feedback, feedback}
    assert feedback =~ "dylan needs_changes: Add one regression test."

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
    decision = Enum.find(history, &(&1["event"] == "inspection_decision"))
    completed = Enum.find(history, &(&1["event"] == "inspection_completed"))

    assert decision["decision"] == "needs_changes"
    assert completed["result"] == "rejected"
  end

  test "unparseable matching reply requires human action without changing state", ctx do
    %{ticket: ticket, prompt: prompt} = request_inspection!(ctx, ["dylan"])

    assert {:ok, %{ticket: pending}} =
             Api.comment_ticket(
               ticket.id,
               %{
                 body: "I cannot return JSON today.",
                 by: "dylan",
                 turn_id: prompt.turn_id,
                 attempt_id: prompt.attempt_id
               },
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z"
             )

    assert pending.state == "pending_approval"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
    assert Enum.any?(history, &match?(%{"event" => "inspection_failed"}, &1))

    completed = Enum.find(history, &(&1["event"] == "inspection_completed"))
    assert completed["result"] == "requires_human"
  end

  test "two-inspector council closes only after both approve", ctx do
    %{ticket: ticket, prompts: [dylan_prompt, elena_prompt]} =
      request_inspection!(ctx, ["dylan", "elena"])

    assert {:ok, %{ticket: still_pending}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("dylan", dylan_prompt, "approve", "Dylan approves."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z"
             )

    assert still_pending.state == "pending_approval"

    assert {:ok, %{ticket: closed}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("elena", elena_prompt, "approve", "Elena approves."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:04:00Z"
             )

    assert closed.state == "closed"
  end

  test "nonmatching inspector comments stay ordinary comments", ctx do
    %{ticket: ticket} = request_inspection!(ctx, ["dylan"])

    assert {:ok, %{ticket: pending}} =
             Api.comment_ticket(
               ticket.id,
               %{
                 body: Jason.encode!(%{"decision" => "approve", "summary" => "Wrong attempt"}),
                 by: "dylan",
                 turn_id: "turn_20260508120300_nomatch000",
                 attempt_id: "attempt_20260508120300_nomatch000"
               },
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z"
             )

    assert pending.state == "pending_approval"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)
    refute Enum.any?(history, &match?(%{"event" => "inspection_decision"}, &1))
    refute Enum.any?(history, &match?(%{"event" => "inspection_completed"}, &1))
  end

  test "duplicate matching replies do not create duplicate decisions", ctx do
    %{ticket: ticket, prompts: [dylan_prompt, elena_prompt]} =
      request_inspection!(ctx, ["dylan", "elena"])

    assert {:ok, %{ticket: pending}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("dylan", dylan_prompt, "approve", "Dylan approves."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z"
             )

    assert pending.state == "pending_approval"

    assert {:ok, %{ticket: still_pending}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment(
                 "dylan",
                 dylan_prompt,
                 "reject",
                 "Duplicate should be ignored."
               ),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:30Z"
             )

    assert still_pending.state == "pending_approval"

    assert {:ok, %{ticket: closed}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("elena", elena_prompt, "approve", "Elena approves."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:04:00Z"
             )

    assert closed.state == "closed"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)

    decisions =
      history
      |> Enum.filter(&(&1["event"] == "inspection_decision"))
      |> Enum.map(&{&1["by"], &1["decision"]})

    assert decisions == [{"dylan", "approve"}, {"elena", "approve"}]
  end

  test "request inspection rejects overlapping active inspection requests", ctx do
    %{ticket: ticket, prompt: old_prompt} = request_inspection!(ctx, ["dylan"])

    assert {:error, {:inspection_already_pending, "insp_20260508120100_1"}} =
             Api.request_inspection(ticket.id,
               root: ctx.config_root,
               tickets_root: ctx.tickets_root,
               inspection_id: "insp_20260508120200_2",
               now: "2026-05-08T12:02:00Z"
             )

    assert {:ok, %{ticket: closed}} =
             Api.comment_ticket(
               ticket.id,
               inspection_comment("dylan", old_prompt, "approve", "Active prompt closes."),
               tickets_root: ctx.tickets_root,
               notify_assignees: false,
               now: "2026-05-08T12:03:00Z"
             )

    assert closed.state == "closed"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: ctx.tickets_root)

    decisions = Enum.filter(history, &(&1["event"] == "inspection_decision"))
    assert Enum.map(decisions, & &1["inspection_id"]) == ["insp_20260508120100_1"]
  end

  defp request_inspection!(ctx, inspectors) do
    for slug <- inspectors do
      write_citizen_toml!(ctx.config_root, slug)
      insert_citizen!(%{slug: slug, roles: ["inspector"]})
    end

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Ready for auto inspection",
                 body: "Confirm the work is complete.",
                 state: "pending_approval",
                 assignees: ["clare"],
                 metadata: %{
                   "inspection" => %{
                     "mode" => "auto",
                     "citizens" => inspectors,
                     "roles" => [],
                     "max_inspectors" => length(inspectors)
                   }
                 }
               },
               tickets_root: ctx.tickets_root,
               date: ~D[2026-05-08],
               now: "2026-05-08T12:00:00Z"
             )

    assert {:ok, result} =
             Api.request_inspection(ticket.id,
               root: ctx.config_root,
               tickets_root: ctx.tickets_root,
               inspection_id: "insp_20260508120100_1",
               now: "2026-05-08T12:01:00Z"
             )

    %{ticket: ticket, prompt: hd(result.prompts), prompts: result.prompts}
  end

  defp inspection_comment(by, prompt, decision, summary) do
    %{
      body:
        Jason.encode!(%{
          "decision" => decision,
          "summary" => summary,
          "findings" => []
        }),
      by: by,
      turn_id: prompt.turn_id,
      attempt_id: prompt.attempt_id
    }
  end
end
