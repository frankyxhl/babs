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

  def message({:not_assigned, id, slug}), do: "Ticket #{id} is not assigned to #{slug}"
  def message({:write_conflict, id}), do: "Ticket #{id} changed while Babs was writing it"

  def message({:redacted_io_error, {operation, _reason}}),
    do: "Ticket IO failed during #{operation}"

  def message({:redacted_io_error, operation}), do: "Ticket IO failed during #{operation}"
  def message(reason), do: "Ticket operation failed: #{inspect(reason)}"
end
