defmodule BabsWeb.TicketPresenterTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Ticket
  alias BabsWeb.TicketPresenter

  test "inspection_panel renders human approval fallback without inspection metadata" do
    panel = TicketPresenter.inspection_panel(ticket(), [])

    assert panel.kind == :human
    assert panel.label == "Human approval"
    assert panel.inspectors == []
    assert panel.result == nil
  end

  test "inspection_panel summarizes auto council decisions and completion" do
    panel =
      ticket(
        metadata: %{
          "inspection" => %{
            "mode" => "auto",
            "strategy" => "council",
            "roles" => ["inspector"],
            "citizens" => ["dylan", "elena"],
            "quorum" => "all_pass",
            "max_inspectors" => 2,
            "allow_self_inspection" => false
          }
        }
      )
      |> TicketPresenter.inspection_panel([
        requested(["dylan", "elena"]),
        prompt_delivered("dylan"),
        prompt_delivered("elena"),
        decision("dylan", "approve", "Looks good."),
        decision("elena", "needs_changes", "Add one screenshot.",
          findings: [%{"path" => "README.md", "body" => "Missing screenshot."}]
        ),
        completed("rejected")
      ])

    assert panel.kind == :auto_council
    assert panel.label == "Auto council"
    assert panel.roles == ["inspector"]
    assert panel.citizens == ["dylan", "elena"]
    assert panel.inspection_id == "insp_20260508120000_1"
    assert panel.result == "rejected"
    assert panel.quorum == "all_pass"

    assert [
             %{slug: "dylan", status: "approve", status_label: "Approved"},
             %{slug: "elena", status: "needs_changes", status_label: "Needs changes"}
           ] = panel.inspectors

    assert List.last(panel.inspectors).summary == "Add one screenshot."
    assert [%{"path" => "README.md"}] = List.last(panel.inspectors).findings
  end

  test "inspection_panel renders failed inspectors without raising" do
    panel =
      ticket(metadata: %{"inspection" => %{"mode" => "auto", "citizens" => ["dylan"]}})
      |> TicketPresenter.inspection_panel([
        requested(["dylan"]),
        %{
          "ts" => "2026-05-08T12:02:00Z",
          "event" => "inspection_failed",
          "by" => "system",
          "ticket_id" => "T-2026-05-08-001",
          "inspection_id" => "insp_20260508120000_1",
          "to" => "dylan",
          "error" => "Inspection failed: unparseable decision"
        }
      ])

    assert [%{slug: "dylan", status: "failed", status_label: "Unparseable or failed"}] =
             panel.inspectors
  end

  test "inspection_panel does not reactivate older requested inspectors" do
    panel =
      ticket(metadata: %{"inspection" => %{"mode" => "auto", "citizens" => ["dylan"]}})
      |> TicketPresenter.inspection_panel([
        requested(["dylan"]),
        Map.put(requested(["elena"]), "inspection_id", "insp_20260508120500_2"),
        %{
          "ts" => "2026-05-08T12:06:00Z",
          "event" => "inspection_completed",
          "by" => "system",
          "ticket_id" => "T-2026-05-08-001",
          "inspection_id" => "insp_20260508120500_2",
          "result" => "requires_human",
          "quorum" => "all_pass"
        }
      ])

    assert panel.inspection_id == "insp_20260508120500_2"
    assert [%{slug: "elena", status: "pending"}] = panel.inspectors
    assert panel.result == "requires_human"
  end

  test "inspection_panel falls back for malformed metadata" do
    panel = TicketPresenter.inspection_panel(ticket(metadata: %{"inspection" => "bad"}), [])

    assert panel.kind == :unavailable
    assert panel.label == "Inspection data unavailable"
  end

  defp ticket(opts \\ []) do
    %Ticket{
      id: "T-2026-05-08-001",
      type: "assignment",
      state: Keyword.get(opts, :state, "pending_approval"),
      assigner: "user",
      assignees: ["clare"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-08T12:00:00Z",
      updated_at: "2026-05-08T12:00:00Z",
      metadata: Keyword.get(opts, :metadata, %{}),
      title: "Ticket",
      body: "Body"
    }
  end

  defp requested(inspectors) do
    %{
      "ts" => "2026-05-08T12:00:00Z",
      "event" => "inspection_requested",
      "by" => "system",
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => "insp_20260508120000_1",
      "policy" => %{"mode" => "auto", "strategy" => "council", "quorum" => "all_pass"},
      "inspectors" => inspectors
    }
  end

  defp prompt_delivered(slug) do
    %{
      "ts" => "2026-05-08T12:01:00Z",
      "event" => "inspection_prompt_delivered",
      "by" => "system",
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => "insp_20260508120000_1",
      "to" => slug,
      "turn_id" => "turn_20260508120100_abcdefghij",
      "attempt_id" => "attempt_20260508120100_abcdefghij"
    }
  end

  defp decision(slug, verdict, summary, opts \\ []) do
    %{
      "ts" => "2026-05-08T12:02:00Z",
      "event" => "inspection_decision",
      "by" => slug,
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => "insp_20260508120000_1",
      "decision" => verdict,
      "summary" => summary,
      "findings" => Keyword.get(opts, :findings, [])
    }
  end

  defp completed(result) do
    %{
      "ts" => "2026-05-08T12:03:00Z",
      "event" => "inspection_completed",
      "by" => "system",
      "ticket_id" => "T-2026-05-08-001",
      "inspection_id" => "insp_20260508120000_1",
      "result" => result,
      "quorum" => "all_pass"
    }
  end
end
