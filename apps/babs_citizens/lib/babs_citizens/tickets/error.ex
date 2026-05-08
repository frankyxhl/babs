defmodule Babs.Citizens.Tickets.Error do
  @moduledoc """
  Stable user-facing error messages for Ticket commands.
  """

  def message({:not_found, id}), do: "Ticket #{id} was not found"
  def message({:invalid_id, id}), do: "Invalid Ticket id: #{inspect(id)}"

  def message({:invalid_frontmatter, reason}),
    do: "Invalid Ticket frontmatter: #{inspect(reason)}"

  def message({:invalid_history, {_id, line, reason}}),
    do: "Invalid Ticket history at line #{line}: #{inspect(reason)}"

  def message({:invalid_history_event, :empty_feedback}),
    do: "Rejection feedback is required"

  def message({:invalid_history_event, :empty_body}),
    do: "Comment body is required"

  def message({:invalid_history_event, reason}),
    do: "Invalid Ticket history event: #{inspect(reason)}"

  def message({:history_event_too_large, id}), do: "Ticket #{id} history event is too large"
  def message({:invalid_state, state}), do: "Invalid Ticket state: #{inspect(state)}"

  def message({:invalid_transition, from, to}),
    do: "Invalid Ticket transition: #{from} -> #{to}"

  def message({:invalid_transition_event, event, expected}),
    do: "Invalid Ticket transition event: #{inspect(event)}; expected #{expected}"

  def message({:use_reject_ticket, id}),
    do: "Ticket #{id} rejection requires feedback; use reject_ticket"

  def message({:use_approve_ticket, id}),
    do: "Ticket #{id} approval requires approve_ticket"

  def message({:no_assignees, id}), do: "Ticket #{id} has no assignees"
  def message({:missing_assignee_role, id}), do: "Ticket #{id} has no assignee role"
  def message({:invalid_assignee_role, value}), do: "Invalid assignee role: #{inspect(value)}"
  def message({:no_role_candidate, role}), do: "No eligible Citizen found for role #{role}"

  def message({:role_route_already_assigned, id}),
    do: "Ticket #{id} already has named assignees"

  def message({:invalid_slug, slug}), do: "Invalid Citizen slug: #{inspect(slug)}"
  def message({:unknown_citizen, slug}), do: "Unknown Citizen: #{slug}"
  def message({:citizen_not_running, slug}), do: "Citizen #{slug} is not running"

  def message({:citizen_start_failed, slug, _reason}),
    do: "Citizen #{slug} could not be started"

  def message({:citizen_lookup_failed, slug, _reason}),
    do: "Citizen #{slug} pane lookup failed"

  def message({:ticket_injection_failed, slug, _reason}),
    do: "Ticket prompt could not be injected into #{slug}"

  def message({:feedback_injection_failed, id, _failures}),
    do: "Ticket #{id} feedback could not be injected into every assignee"

  def message({:invalid_comment_author, value}),
    do: "Invalid Ticket comment author: #{inspect(value)}"

  def message({:mayor_proposal_review, :no_proposal}), do: "No Mayor proposal is available"

  def message({:mayor_proposal_review, {:invalid_policy, reason}}),
    do: "Invalid Mayor policy: #{inspect(reason)}"

  def message({:mayor_proposal_review, {:invalid_proposal, reason}}),
    do: "Invalid Mayor proposal: #{inspect(reason)}"

  def message({:mayor_proposal_review, {:stale_proposal_id, expected, actual}}),
    do: "Mayor proposal changed: expected #{expected}, got #{actual}"

  def message({:mayor_proposal_review, {:stale_proposal_revision, _expected, _actual}}),
    do: "Mayor proposal changed; refresh before editing again"

  def message({:mayor_proposal_review, {:invalid_child_index, index}}),
    do: "Invalid proposal child index: #{inspect(index)}"

  def message({:mayor_proposal_review, {:invalid_edit, reason}}),
    do: "Invalid proposal edit: #{inspect(reason)}"

  def message({:mayor_proposal_review, :empty_feedback}),
    do: "Proposal rejection feedback is required"

  def message({:mayor_proposal_review, {:already_decided, status}}),
    do: "Mayor proposal is already #{status}"

  def message({:mayor_proposal_review, {:terminal_ticket, id, state}}),
    do: "Ticket #{id} is #{state} and cannot review Mayor proposals"

  def message({:mayor_child_tickets, {:partial_child_write, created_ids, _reason}})
      when is_list(created_ids) do
    "Mayor proposal created #{length(created_ids)} child Ticket before failing; review created child Tickets before retrying"
  end

  def message({:terminal_ticket, id, state}),
    do: "Ticket #{id} is #{state} and cannot be commented on"

  def message({:comment_notification_failed, id, _failures}),
    do: "Ticket #{id} comment notification failed for one or more assignees"

  def message({:not_assigned, id, slug}), do: "Ticket #{id} is not assigned to #{slug}"
  def message({:write_conflict, id}), do: "Ticket #{id} changed while Babs was writing it"

  def message({:redacted_io_error, {operation, _reason}}),
    do: "Ticket IO failed during #{operation}"

  def message({:redacted_io_error, operation}), do: "Ticket IO failed during #{operation}"
  def message(reason), do: "Ticket operation failed: #{inspect(reason)}"
end
