defmodule Babs.Citizens.Tickets.ErrorTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Error

  test "renders redacted IO errors without host paths or raw reasons" do
    message = Error.message({:redacted_io_error, {:read_ticket, {:eacces, "/private/path"}}})

    assert message == "Ticket IO failed during read_ticket"
    refute message =~ "/private/path"
    refute message =~ "eacces"
  end

  test "renders stable typed ticket errors" do
    assert Error.message({:not_found, "T-2026-05-06-001"}) ==
             "Ticket T-2026-05-06-001 was not found"

    assert Error.message({:write_conflict, "T-2026-05-06-001"}) =~
             "changed while Babs was writing"

    assert Error.message({:invalid_transition, "pending_approval", "open"}) ==
             "Invalid Ticket transition: pending_approval -> open"

    assert Error.message({:use_reject_ticket, "T-2026-05-06-001"}) =~
             "rejection requires feedback"

    assert Error.message({:use_approve_ticket, "T-2026-05-06-001"}) =~
             "approval requires approve_ticket"

    assert Error.message({:invalid_history_event, :empty_feedback}) ==
             "Rejection feedback is required"

    assert Error.message({:invalid_history_event, :empty_body}) ==
             "Comment body is required"

    assert Error.message({:no_assignees, "T-2026-05-06-001"}) ==
             "Ticket T-2026-05-06-001 has no assignees"

    assert Error.message({:invalid_slug, ""}) == "Invalid Citizen slug: \"\""

    assert Error.message({:invalid_comment_author, "not valid"}) ==
             "Invalid Ticket comment author: \"not valid\""

    assert Error.message({:unknown_citizen, "ghost"}) == "Unknown Citizen: ghost"

    assert Error.message({:terminal_ticket, "T-2026-05-06-001", "closed"}) ==
             "Ticket T-2026-05-06-001 is closed and cannot be commented on"

    assert Error.message({:citizen_start_failed, "clare", "raw credential value"}) ==
             "Citizen clare could not be started"

    assert Error.message({:citizen_lookup_failed, "clare", "raw credential value"}) ==
             "Citizen clare pane lookup failed"

    assert Error.message({:ticket_injection_failed, "clare", "raw credential value"}) ==
             "Ticket prompt could not be injected into clare"

    assert Error.message({:feedback_injection_failed, "T-2026-05-06-001", []}) ==
             "Ticket T-2026-05-06-001 feedback could not be injected into every assignee"

    assert Error.message({:comment_notification_failed, "T-2026-05-06-001", []}) ==
             "Ticket T-2026-05-06-001 comment notification failed for one or more assignees"

    assert Error.message({:mayor_proposal_review, {:invalid_policy, {:invalid_mayor, 42}}}) ==
             "Invalid Mayor policy: {:invalid_mayor, 42}"
  end
end
